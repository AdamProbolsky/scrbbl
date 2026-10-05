import Foundation
import PencilKit
import Security
import UIKit

@MainActor
final class NoteCanvasModel: ObservableObject {
    @Published var drawing = PKDrawing()
    @Published var answer: String?
    @Published var isProcessing = false
    @Published var recognizedQuestion = ""
    /// How long the last answer took: time to first words, and to finish.
    @Published var timing = ""
    @Published var statusText = "Thinking…"
    @Published var apiKey = APIKeyStore.load() ?? ""
    @Published var speed: AnswerSpeed = AnswerSpeed.saved {
        didSet { speed.save() }
    }

    private let triggerDetector = TripleUnderlineDetector()
    // Incremented by `clear()` so a reply that arrives after clearing is dropped.
    private var requestGeneration = 0

    func drawingChanged(_ drawing: PKDrawing) {
        let previousStrokeCount = self.drawing.strokes.count
        self.drawing = drawing

        // Only react to newly added strokes. Erasing, undoing, or clearing must
        // not re-fire a gesture that is still on the page.
        guard drawing.strokes.count > previousStrokeCount,
              let trigger = triggerDetector.trigger(in: drawing) else { return }
        answerQuestion(from: drawing, trigger: trigger)
    }

    func clear() {
        requestGeneration += 1
        drawing = PKDrawing()
        answer = nil
        recognizedQuestion = ""
        isProcessing = false
    }

    enum KeySaveResult {
        case saved, removed, failed
    }

    func saveAPIKey() -> KeySaveResult {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard APIKeyStore.save(apiKey) else { return .failed }
        return apiKey.isEmpty ? .removed : .saved
    }

    private func answerQuestion(from drawing: PKDrawing, trigger: GestureTrigger) {
        guard !isProcessing else { return }
        guard !apiKey.isEmpty else {
            answer = "Add an API key in Settings to ask the AI."
            return
        }
        isProcessing = true
        let generation = requestGeneration
        let apiKey = apiKey

        let questionStrokes = QuestionLocator.strokes(for: trigger, in: drawing)
        guard let image = Self.recognitionImage(of: questionStrokes) else {
            // Lines with no writing near them: nothing to ask, so stay quiet.
            isProcessing = false
            return
        }

        answer = nil
        recognizedQuestion = ""
        timing = ""
        statusText = "Thinking…"
        let speed = speed
        let started = Date()
        var firstWords: TimeInterval?

        Task { @MainActor in
            // The AI reads a picture of the handwriting directly, and the answer
            // streams in so the first words appear almost immediately.
            do {
                try await AIClient(apiKey: apiKey, speed: speed).answer(
                    handwriting: image,
                    detail: trigger.detail,
                    onSearching: { [weak self] in
                        guard let self, generation == requestGeneration else { return }
                        statusText = "Searching the web…"
                    }
                ) { [weak self] reply in
                    guard let self, generation == requestGeneration else { return }
                    // Hold back anything that is (or may become) the no-question marker.
                    let marker = AIClient.noQuestionMarker
                    guard !reply.answer.hasPrefix(marker), !marker.hasPrefix(reply.answer),
                          !reply.question.hasPrefix(marker) else { return }
                    recognizedQuestion = reply.question
                    if !reply.answer.isEmpty {
                        if firstWords == nil { firstWords = Date().timeIntervalSince(started) }
                        answer = reply.answer
                    }
                }
            } catch {
                guard generation == requestGeneration else { return }
                answer = "AI request failed: \(error.localizedDescription)"
            }
            guard generation == requestGeneration else { return }
            // No answer means there was no readable question: stay quiet.
            if let firstWords {
                let total = Date().timeIntervalSince(started)
                timing = String(format: "first words %.1fs · done %.1fs", firstWords, total)
            }
            isProcessing = false
        }
    }

    /// Renders strokes as dark ink on an opaque white background, regardless of
    /// the system appearance, so the AI sees the handwriting clearly.
    private static func recognitionImage(of strokes: [PKStroke]) -> CGImage? {
        guard !strokes.isEmpty else { return nil }
        let questionDrawing = PKDrawing(strokes: strokes)
        let rect = questionDrawing.bounds.insetBy(dx: -20, dy: -20)

        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = questionDrawing.image(from: rect, scale: 1.5)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = ink.scale
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: ink.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
        return flattened.cgImage
    }
}

enum AnswerDetail {
    case short
    case comprehensive

    var instruction: String {
        switch self {
        case .short:
            return "Give a direct, substantive answer in two to four sentences, with concrete specifics rather than generalities."
        case .comprehensive:
            return "Give a thorough, expert answer with concrete facts, examples, and specifics, in about 200 to 350 words."
        }
    }
}

/// Fast answers by default; Smart trades speed for depth.
enum AnswerSpeed: String, CaseIterable, Identifiable {
    case fast
    case smart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "Fast (GPT-6 Luna)"
        case .smart: return "Smart (GPT-6.1 Sol, slower, deeper)"
        }
    }

    var model: String {
        switch self {
        case .fast: return "gpt-6-luna"
        case .smart: return "gpt-6.1-sol"
        }
    }

    private static let defaultsKey = "scrbbl.answer-speed"

    static var saved: AnswerSpeed {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AnswerSpeed.init) ?? .fast
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

struct AIClient {
    let apiKey: String
    let speed: AnswerSpeed

    enum ClientError: LocalizedError {
        case http(status: Int, message: String?)
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case let .http(status, message):
                return message ?? "The server returned status \(status)."
            case .emptyAnswer:
                return "The response did not contain any text."
            }
        }
    }

    /// The model's reply when there is no readable question; the app then stays quiet.
    static let noQuestionMarker = "NO_QUESTION"

    struct Reply {
        let question: String
        let answer: String
    }

    /// Streams the answer, calling `onUpdate` on the main actor as text arrives.
    func answer(
        handwriting: CGImage,
        detail: AnswerDetail,
        onSearching: @escaping @MainActor () -> Void,
        onUpdate: @escaping @MainActor (Reply) -> Void
    ) async throws {
        guard let jpeg = UIImage(cgImage: handwriting).jpegData(compressionQuality: 0.8) else {
            throw ClientError.emptyAnswer
        }

        var body: [String: Any] = [
            "model": speed.model,
            "stream": true,
            "instructions": """
                The image is a question handwritten with Apple Pencil. Read the handwriting carefully. \
                Answer like a knowledgeable expert: be specific and substantive, never vague or generic. \
                Use web search whenever the answer depends on anything current or time-sensitive: news, \
                prices, scores, weather, people's current roles, recent releases, or anything that may have \
                changed lately. For timeless questions, answer immediately without searching. \
                Reply in plain text only: no Markdown, no LaTeX, no links, no citations, no special formatting symbols. \
                The first line must be exactly "Question: " followed by the question as you read it. \
                Then a blank line, then the answer. \(detail.instruction) \
                Never comment on the handwriting or ask the person to rewrite anything. If the writing \
                is not a question or is impossible to read, reply with exactly \(Self.noQuestionMarker) and nothing else.
                """,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]
                ]
            ]]
        ]
        // Web search is always available; the model decides per question.
        body["tools"] = [["type": "web_search"]]
        switch speed {
        case .fast:
            // GPT-6 models reason before answering by default ("medium"), which
            // is most of the wait. Fast mode skips that and asks for OpenAI's
            // fast processing tier.
            body["reasoning"] = ["effort": "none"]
            body["service_tier"] = "fast"
        case .smart:
            body["reasoning"] = ["effort": "low"]
        }

        var (bytes, status) = try await send(body)
        var retries = 0
        while !(200..<300).contains(status) {
            let message = try await errorMessage(from: bytes) ?? ""
            // Fall back gracefully if this model or account rejects an option:
            // the fast tier, or web search without any reasoning.
            guard status == 400, retries < 2 else {
                throw ClientError.http(status: status, message: message.isEmpty ? nil : message)
            }
            if message.contains("service_tier"), body["service_tier"] != nil {
                body.removeValue(forKey: "service_tier")
            } else if message.contains("reasoning") || message.contains("effort") || message.contains("web_search") {
                body["reasoning"] = ["effort": "low"]
            } else {
                throw ClientError.http(status: status, message: message)
            }
            retries += 1
            (bytes, status) = try await send(body)
        }

        // Server-sent events: each `data:` line is a JSON event. Text arrives as
        // `response.output_text.delta` events.
        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = Data(line.dropFirst("data:".count).utf8)
            guard let event = try? JSONDecoder().decode(StreamEvent.self, from: payload) else { continue }
            switch event.type {
            case "response.output_text.delta":
                text += event.delta ?? ""
                let reply = Self.split(text)
                await onUpdate(reply)
            case let type where type.hasPrefix("response.web_search_call"):
                await onSearching()
            case "error", "response.failed":
                throw ClientError.http(status: status, message: event.message ?? event.response?.error?.message)
            default:
                continue
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.emptyAnswer }
    }

    private func send(_ body: [String: Any]) async throws -> (URLSession.AsyncBytes, Int) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        return (bytes, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func errorMessage(from bytes: URLSession.AsyncBytes) async throws -> String? {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error.message
    }

    /// Separates the "Question: ..." first line from the answer that follows.
    /// Works on partial text while the answer is still streaming in.
    private static func split(_ text: String) -> Reply {
        guard text.lowercased().hasPrefix("question:") else {
            return Reply(question: "", answer: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let newline = text.firstIndex(of: "\n") else {
            // Still receiving the question line.
            let question = text.dropFirst("question:".count).trimmingCharacters(in: .whitespaces)
            return Reply(question: question, answer: "")
        }
        let question = text[..<newline].dropFirst("question:".count).trimmingCharacters(in: .whitespaces)
        let answer = text[newline...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Reply(question: question, answer: answer)
    }

    private struct StreamEvent: Decodable {
        struct ResponseInfo: Decodable {
            struct ErrorInfo: Decodable { let message: String? }
            let error: ErrorInfo?
        }

        let type: String
        let delta: String?
        let message: String?
        let response: ResponseInfo?
    }

    private struct APIErrorBody: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

/// Stores the API key in the Keychain, readable only on this device while unlocked.
enum APIKeyStore {
    private static let service = "scrbbl"
    private static let account = "openai-api-key"

    static func load() -> String? {
        #if DEBUG
        // Development convenience: `scripts/launch-with-key.command` passes a key
        // through the launch environment, which is saved like one typed in Settings.
        if let injected = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !injected.isEmpty {
            save(injected)
            return injected
        }
        #endif

        return readKeychain()
    }

    /// Replaces the stored key; an empty value removes it. Returns whether the
    /// Keychain accepted the change.
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return true }

        var item = baseQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
