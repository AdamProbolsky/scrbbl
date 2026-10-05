import SwiftUI

struct ContentView: View {
    @StateObject private var model = NoteCanvasModel()

    var body: some View {
        NavigationStack {
            NoteCanvasView(model: model)
                .navigationTitle("Scrbbl AI")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            model.clear()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Settings") {
                            SettingsView(model: model)
                        }
                    }
                }
        }
    }
}
