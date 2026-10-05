import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: NoteCanvasModel
    @State private var saveResult: NoteCanvasModel.KeySaveResult?
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        Form {
            Section("AI connection") {
                SecureField("OpenAI API key", text: $model.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($keyFieldFocused)
                    .onChange(of: model.apiKey) { saveResult = nil }
                Button("Save API key") {
                    keyFieldFocused = false
                    saveResult = model.saveAPIKey()
                }
                if let saveResult {
                    Label(saveMessage(for: saveResult), systemImage: saveResult == .failed
                          ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(saveResult == .failed ? .primary : .secondary)
                }
                Text("The key is stored in this device's Keychain. Do not ship a public app with provider keys embedded in the app; a production release should use a secure backend or an approved user authorization flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Answer speed") {
                Picker("Model", selection: $model.speed) {
                    ForEach(AnswerSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Response style") {
                Text("Triple underline text for a short answer.")
                Text("Circle the text for a fuller answer with examples.")
            }
        }
        .navigationTitle("Settings")
    }

    private func saveMessage(for result: NoteCanvasModel.KeySaveResult) -> String {
        switch result {
        case .saved: return "API key saved."
        case .removed: return "API key removed."
        case .failed: return "Couldn't save the key. Try again."
        }
    }
}
