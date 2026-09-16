import SwiftUI

struct ContentView: View {
    @ObservedObject var document: EditorDocument
    var project: ProjectContext?
    let openFile: (URL) -> Void
    @State private var editorStatus = EditorStatus()

    var body: some View {
        NavigationSplitView {
            if let project { ProjectSidebar(project: project, openFile: openFile) } else { Text("Open a folder to browse a project").foregroundStyle(.secondary).padding() }
        } detail: {
            if document.fileURL == nil {
                Text("Open a file to start editing")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    NativeTextEditor(
                        text: Binding(
                            get: { document.text },
                            set: { document.updateText($0) }
                        ),
                        status: $editorStatus,
                        language: LanguageDetector.language(for: document.fileURL),
                        indentationWidth: document.indentationWidth,
                        caretSourceOffset: Binding(get: { document.caretSourceOffset }, set: document.updateCaretSourceOffset),
                        navigationTarget: Binding(get: { document.navigationTargetSourceOffset }, set: { document.navigationTargetSourceOffset = $0 })
                    )
                    .id(document.presentationGeneration)

                    EditorStatusBar(
                        status: EditorStatus(
                            position: editorStatus.position,
                            languageName: LanguageDetector.language(for: document.fileURL)?.displayName ?? "Plain Text",
                            indentationWidth: document.indentationWidth
                        )
                    )
                }
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
    ContentView(document: EditorDocument(), project: nil, openFile: { _ in })
}
