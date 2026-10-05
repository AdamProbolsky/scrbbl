import PencilKit
import SwiftUI

struct NoteCanvasView: View {
    @ObservedObject var model: NoteCanvasModel
    @State private var answerHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            PencilCanvasRepresentable(
                drawing: $model.drawing,
                onDrawingChanged: model.drawingChanged
            )
            .background(Color.white)
            .ignoresSafeArea(edges: .bottom)

            if let answer = model.answer {
                VStack(alignment: .leading, spacing: 6) {
                    if !model.recognizedQuestion.isEmpty || !model.timing.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            if !model.recognizedQuestion.isEmpty {
                                Text("Read as: \(model.recognizedQuestion)")
                            }
                            Spacer(minLength: 8)
                            Text(model.timing)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    // The box hugs short answers; long ones scroll instead of
                    // running off the screen.
                    ScrollView {
                        answerText(answer)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                answerHeight = $0
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(max(answerHeight, 1), 420))
                }
                    .padding(14)
                    .frame(maxWidth: 620, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
            }

            if model.isProcessing && model.answer == nil {
                ProgressView(model.statusText)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
        }
    }

    private func answerText(_ answer: String) -> some View {
        Text(answer)
            // Nothing You Could Do is a bundled font that looks like quick
            // ballpoint handwriting; see ScrbblApp for registration.
            .font(.custom("NothingYouCouldDo", size: 26))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let onDrawingChanged: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        #if targetEnvironment(simulator)
        // The simulator has no Apple Pencil, so allow mouse and trackpad input.
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
        // Keep black ink black on the white page in Dark Mode.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .white
        canvas.alwaysBounceVertical = true
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void

        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
