import SwiftUI

struct ContentView: View {
    @ObservedObject var session: EditorSession
    var applicationDelegate: ScopeApplicationDelegate? = nil
    @AppStorage("sidebarPosition") private var sidebarPosition = SidebarPosition.left.rawValue

    private enum Pane: Hashable { case sidebar, editor }

    private var panes: [Pane] {
        sidebarPosition == SidebarPosition.right.rawValue ? [.editor, .sidebar] : [.sidebar, .editor]
    }

    var body: some View {
        HSplitView {
            ForEach(panes, id: \.self) { pane in
                switch pane {
                case .sidebar:
                    sidebar.frame(minWidth: 160, idealWidth: 220, maxWidth: 360)
                case .editor:
                    documentArea.frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WorkspaceWindowPresentation(session: session, applicationDelegate: applicationDelegate))
    }

    @ViewBuilder private var sidebar: some View {
        if let project = session.project {
            ProjectSidebar(project: project, activeFileURL: session.activeDocument?.fileURL, openFile: { session.open($0) })
        } else {
            Text("Open a folder to browse a project")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var documentArea: some View {
        VStack(spacing: 0) {
            if !session.documents.isEmpty {
                DocumentBar(documents: session.documents, activeDocument: session.activeDocument, activate: session.activate, close: session.close)
            }
            if session.activeDocument == nil {
                Text("Open a file to start editing")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ZStack {
                ForEach(session.documents) { document in
                    let active = document === session.activeDocument
                    DocumentEditorPane(document: document, isActive: active)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                }
            }
        }
    }
}

private struct DocumentEditorPane: View {
    @ObservedObject var document: EditorDocument
    let isActive: Bool
    @State private var hasMounted = false
    @State private var editorStatus = EditorStatus()

    var body: some View {
        if isActive || hasMounted {
            VStack(spacing: 0) {
                NativeTextEditor(
                    text: Binding(get: { document.text }, set: document.updateText),
                    status: $editorStatus,
                    language: LanguageDetector.language(for: document.fileURL),
                    indentationWidth: document.indentationWidth,
                    caretSourceOffset: Binding(get: { document.caretSourceOffset }, set: document.updateCaretSourceOffset),
                    navigationTarget: $document.navigationTargetSourceOffset,
                    isActive: isActive
                )
                .id(document.presentationGeneration)
                EditorStatusBar(status: editorStatus)
            }
            .onAppear { hasMounted = true }
        }
    }
}

private struct WorkspaceWindowPresentation: View {
    @ObservedObject var session: EditorSession
    let applicationDelegate: ScopeApplicationDelegate?

    var body: some View {
        if let document = session.activeDocument {
            DocumentWindowPresentation(document: document, attach: attach)
        } else {
            WindowPresentation(title: "Scope", isDocumentEdited: false, attach: attach)
        }
    }

    private func attach(_ window: NSWindow) {
        applicationDelegate?.attach(window, session: session)
    }
}

private struct DocumentWindowPresentation: View {
    @ObservedObject var document: EditorDocument
    let attach: (NSWindow) -> Void

    var body: some View {
        WindowPresentation(title: document.windowTitle, isDocumentEdited: document.isDirty, attach: attach)
    }
}

#Preview {
    ContentView(session: EditorSession(restoreSession: false))
}
