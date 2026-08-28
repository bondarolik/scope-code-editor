import SwiftUI

struct ContentView: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        Group {
            if document.fileURL == nil {
                Text("Open a file to start editing")
                    .foregroundStyle(.secondary)
            } else {
                NativeTextEditor(
                    text: Binding(
                        get: { document.text },
                        set: { document.updateText($0) }
                    ),
                    language: LanguageDetector.language(for: document.fileURL)
                )
            }
        }
        .navigationTitle(document.windowTitle)
        .background(
            WindowPresentation(
                title: document.windowTitle,
                isDocumentEdited: document.isDirty
            )
        )
    }
}

#Preview {
    ContentView(document: EditorDocument())
}
