import SwiftUI

struct ContentView: View {
    @ObservedObject var session: EditorSession
    @AppStorage("sidebarPosition") private var sidebarPosition = SidebarPosition.left.rawValue
    @State private var editorStatus = EditorStatus()

    var body: some View {
        Group {
            if sidebarPosition == SidebarPosition.right.rawValue {
                HSplitView { documentArea; sidebar }
            } else {
                HSplitView { sidebar; documentArea }
            }
        }
        .background(
            WindowPresentation(
                title: session.activeDocument?.windowTitle ?? "Scope",
                isDocumentEdited: session.activeDocument?.isDirty ?? false
            )
        )
    }

    @ViewBuilder private var sidebar: some View {
        if let project = session.project {
            ProjectSidebar(project: project, activeFileURL: session.activeDocument?.fileURL, openFile: { session.open($0) })
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 360)
        } else {
            Text("Open a folder to browse a project").foregroundStyle(.secondary).frame(minWidth: 160, idealWidth: 220, maxWidth: 360, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var documentArea: some View {
        VStack(spacing: 0) {
            if !session.documents.isEmpty { DocumentBar(documents: session.documents, activeDocument: session.activeDocument, activate: session.activate, close: session.close) }
            if let document = session.activeDocument {
                NativeTextEditor(text: Binding(get: { document.text }, set: document.updateText), status: $editorStatus, language: LanguageDetector.language(for: document.fileURL), indentationWidth: document.indentationWidth, caretSourceOffset: Binding(get: { document.caretSourceOffset }, set: document.updateCaretSourceOffset), navigationTarget: Binding(get: { document.navigationTargetSourceOffset }, set: { document.navigationTargetSourceOffset = $0 }))
                    .id(document.id.uuidString + "-" + String(document.presentationGeneration))
                EditorStatusBar(status: EditorStatus(position: editorStatus.position, languageName: LanguageDetector.language(for: document.fileURL)?.displayName ?? "Plain Text", indentationWidth: document.indentationWidth))
            } else {
                Text("Open a file to start editing").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    ContentView(session: EditorSession(restoreSession: false))
}
