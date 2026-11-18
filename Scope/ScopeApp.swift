import AppKit
import SwiftUI
import Combine

@main struct ScopeApp: App {
    @NSApplicationDelegateAdaptor(ScopeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var session = EditorSession()

    var body: some Scene {
        Window("Scope", id: "workspace") {
            ContentView(session: session, applicationDelegate: applicationDelegate)
                .frame(minWidth: 600, minHeight: 400)
                .sheet(isPresented: $session.quickOpenPresented) {
                    if let project = session.project {
                        QuickOpenSheet(project: project) {
                            session.quickOpenPresented = false
                            session.open($0.url)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { session.chooseFile(in: applicationDelegate.workspaceWindow) }.keyboardShortcut("o", modifiers: .command)
                Button("Open Last Used") { session.openLastUsed() }.disabled(session.recentFiles.mostRecentFile == nil)
                Menu("Open Recent") { ForEach(session.recentFiles.menuTitles(), id: \.file) { item in Button(item.title) { session.openRecentFile(item.file) } } }.disabled(session.recentFiles.files.isEmpty)
                Button("Open Folder…") { session.chooseFolder(in: applicationDelegate.workspaceWindow) }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Quick Open") { session.quickOpen() }.keyboardShortcut("p", modifiers: .command).disabled(session.project == nil)
                Button("Go to Definition") { session.goToDefinition() }.keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(session.project == nil)
                Button("Navigate Back") { session.back() }.keyboardShortcut(.leftArrow, modifiers: [.command, .control]).disabled(!session.history.canGoBack)
                Button("Navigate Forward") { session.forward() }.keyboardShortcut(.rightArrow, modifiers: [.command, .control]).disabled(!session.history.canGoForward)
                Divider()
                Button("Save") { session.save() }.keyboardShortcut("s", modifiers: .command).disabled(session.activeDocument == nil)
            }
        }
        Settings { ScopeSettingsView() }
    }
}

@MainActor final class EditorSession: ObservableObject {
    private struct DocumentSlot {
        let id: UUID
        var bookmark: RestorableDocument?
        var document: EditorDocument?
        var folderAccess: ProjectFolderAccess?
    }

    @Published private var slots: [DocumentSlot] = []
    @Published private(set) var activeDocument: EditorDocument?
    @Published private(set) var project: ProjectContext?
    @Published var quickOpenPresented = false
    let history = NavigationHistory()
    let recentFiles = RecentFileStore()
    private let documentSessionStore: DocumentSessionStore
    private let bookmarks: WorkspaceBookmarks
    private var preferredDocumentID: UUID?
    private var projectBookmark: RestorableProject?
    private var symbols = SymbolIndex.empty
    private(set) var isConfirmingClose = false

    init(
        documentSessionStore: DocumentSessionStore? = nil,
        bookmarks: WorkspaceBookmarks? = nil,
        restoreSession: Bool = true
    ) {
        self.documentSessionStore = documentSessionStore ?? DocumentSessionStore()
        self.bookmarks = bookmarks ?? .securityScoped
        if restoreSession { restoreWorkspace() }
    }

    var documents: [EditorDocument] { slots.compactMap(\.document) }
    var hasDirtyDocuments: Bool { documents.contains(where: \.isDirty) }

    func chooseFile(in window: NSWindow?) {
        chooseItem(in: window, directory: false) { self.open($0) }
    }
    func openLastUsed() { guard let file = recentFiles.mostRecentFile else { return }; openRecentFile(file) }
    func openRecentFile(_ file: RecentFile) {
        do { open(try recentFiles.resolveURL(for: file), replacing: file) }
        catch { recentFiles.remove(file); alert(error, "Couldn’t Open File") }
    }
    func chooseFolder(in window: NSWindow?) {
        chooseItem(in: window, directory: true, openProject)
    }

    private func chooseItem(in window: NSWindow?, directory: Bool, _ selected: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { selected(url) }
        }
        if let window {
            guard window.attachedSheet == nil else { return }
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func openProject(_ url: URL) {
        installProject(at: url)
        if let data = try? bookmarks.make(url) {
            projectBookmark = RestorableProject(bookmarkData: data)
        }
        persistWorkspace()
    }

    func open(_ url: URL, target: Int? = nil, recordRecent: Bool = true, replacing recentFile: RecentFile? = nil) {
        let identity = url.standardizedFileURL
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == identity }) {
            if let target { existing.navigationTargetSourceOffset = target }
            activate(existing)
            if recordRecent { recentFiles.recordSuccessfulOpen(existing.fileURL ?? url, replacing: recentFile) }
            return
        }
        let existingSlot = slots.firstIndex { slot in
            guard slot.document == nil, let path = slot.bookmark?.displayPath else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL == identity
        }
        let document = EditorDocument(id: existingSlot.map { slots[$0].id } ?? UUID())
        do {
            try document.load(from: url)
        } catch {
            if let recentFile { recentFiles.remove(recentFile) }
            alert(error, "Couldn’t Open File")
            return
        }
        document.navigationTargetSourceOffset = target
        let bookmark = makeBookmark(for: document)
        let access = folderAccess(for: url)
        if let existingSlot {
            slots[existingSlot].document = document
            slots[existingSlot].folderAccess = access
            if let bookmark { slots[existingSlot].bookmark = bookmark }
        } else {
            slots.append(DocumentSlot(id: document.id, bookmark: bookmark, document: document, folderAccess: access))
        }
        activate(document)
        if recordRecent { recentFiles.recordSuccessfulOpen(url, replacing: recentFile) }
    }

    func activate(_ document: EditorDocument) {
        guard slots.contains(where: { $0.document === document }) else { return }
        activeDocument = document
        preferredDocumentID = document.id
        persistWorkspace()
    }

    func close(_ document: EditorDocument) {
        guard slots.contains(where: { $0.document === document }), !isConfirmingClose else { return }
        confirmChanges(to: document.isDirty ? [document] : [], in: NSApp.keyWindow) { approved in
            if approved { self.remove(document) }
        }
    }

    func save() {
        guard let activeDocument else { return }
        do { try save(activeDocument) }
        catch { alert(error, "Couldn’t Save File") }
    }

    func quickOpen() { quickOpenPresented = true }

    func goToDefinition() {
        guard let document = activeDocument, let file = document.fileURL, let word = identifier(in: document), let entry = symbols.lookup(word).first else { return }
        let offset = sourceOffset(line: entry.line, fileURL: entry.fileURL)
        history.record(.init(fileURL: file, sourceOffset: document.caretSourceOffset)); history.record(.init(fileURL: entry.fileURL, sourceOffset: offset))
        open(entry.fileURL, target: offset)
    }
    func back() { if let target = history.back() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    func forward() { if let target = history.forward() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    func confirmCloseAll(in window: NSWindow?, completion: @escaping (Bool) -> Void) {
        confirmChanges(to: documents.filter(\.isDirty), in: window, completion: completion)
    }

    private func remove(_ document: EditorDocument) {
        guard let index = slots.firstIndex(where: { $0.document === document }) else { return }
        slots.remove(at: index)
        if activeDocument === document {
            activeDocument = slots.dropFirst(index).compactMap(\.document).first ?? documents.last
        }
        if preferredDocumentID == document.id { preferredDocumentID = activeDocument?.id }
        persistWorkspace()
    }

    private func save(_ document: EditorDocument) throws {
        try document.save()
        guard let index = slots.firstIndex(where: { $0.document === document }),
              let bookmark = makeBookmark(for: document) else { return }
        slots[index].bookmark = bookmark
        persistWorkspace()
    }

    private func confirmChanges(
        to documents: [EditorDocument],
        in window: NSWindow?,
        completion: @escaping (Bool) -> Void
    ) {
        guard !isConfirmingClose else { completion(false); return }
        guard !documents.isEmpty else { completion(true); return }
        isConfirmingClose = true
        confirmNext(documents[...], in: window) { approved in
            self.isConfirmingClose = false
            completion(approved)
        }
    }

    private func confirmNext(
        _ documents: ArraySlice<EditorDocument>,
        in window: NSWindow?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let document = documents.first else { completion(true); return }
        let prompt = NSAlert()
        prompt.messageText = "Do you want to save the changes you made to \(document.windowTitle)?"
        prompt.addButton(withTitle: "Save")
        prompt.addButton(withTitle: "Don’t Save")
        prompt.addButton(withTitle: "Cancel")
        prompt.buttons[2].keyEquivalent = "\u{1b}"

        present(prompt, in: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                do { try self.save(document) }
                catch {
                    let failure = NSAlert(error: error)
                    failure.messageText = "Couldn’t Save File"
                    self.present(failure, in: window) { _ in completion(false) }
                    return
                }
            case .alertSecondButtonReturn:
                break
            default:
                completion(false)
                return
            }
            self.confirmNext(documents.dropFirst(), in: window, completion: completion)
        }
    }

    private func present(_ prompt: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible, window.attachedSheet == nil {
            prompt.beginSheetModal(for: window) { response in
                DispatchQueue.main.async { completion(response) }
            }
        } else {
            completion(prompt.runModal())
        }
    }

    private func restoreWorkspace() {
        let saved = documentSessionStore.load()
        preferredDocumentID = saved.activeDocumentID
        projectBookmark = saved.project
        var refreshed = false
        if let project = saved.project, let resolved = try? bookmarks.resolve(project.bookmarkData) {
            installProject(at: resolved.url)
            if resolved.isStale, let data = try? bookmarks.make(resolved.url) {
                projectBookmark = RestorableProject(bookmarkData: data)
                refreshed = true
            }
        }
        slots = saved.documents.map { entry in
            var slot = DocumentSlot(id: entry.id, bookmark: entry)
            guard let resolved = try? bookmarks.resolve(entry.bookmarkData) else { return slot }
            let document = EditorDocument(id: entry.id)
            do { try document.load(from: resolved.url) }
            catch { return slot }
            slot.document = document
            slot.folderAccess = folderAccess(for: resolved.url)
            if resolved.isStale, let bookmark = makeBookmark(for: document) {
                slot.bookmark = bookmark
                refreshed = true
            }
            return slot
        }
        activeDocument = documents.first(where: { $0.id == preferredDocumentID }) ?? documents.first
        if refreshed { persistWorkspace() }
    }

    private func makeBookmark(for document: EditorDocument) -> RestorableDocument? {
        guard let url = document.fileURL, let data = try? bookmarks.make(url) else { return nil }
        return RestorableDocument(id: document.id, bookmarkData: data, displayPath: url.path)
    }

    private func folderAccess(for url: URL) -> ProjectFolderAccess? {
        guard let access = project?.folderAccess,
              url.standardizedFileURL.pathComponents.starts(with: access.url.standardizedFileURL.pathComponents) else {
            return nil
        }
        // Files opened through a folder can still need that grant after switching projects.
        return access
    }

    private func persistWorkspace() {
        documentSessionStore.save(.init(
            documents: slots.compactMap(\.bookmark),
            activeDocumentID: preferredDocumentID,
            project: projectBookmark
        ))
    }

    private func installProject(at url: URL) {
        project?.cancelScan()
        let context = ProjectContext(rootURL: url)
        project = context
        context.buildFileIndex()
        symbols = .empty
        Task { [weak self, weak context, access = context.folderAccess] in
            let result = await Task.detached(priority: .userInitiated) {
                withExtendedLifetime(access) { CtagsRunner.buildIndex(rootURL: access.url) }
            }.value
            guard let self, let context, self.project === context else { return }
            self.symbols = result
        }
    }

    private func identifier(in document: EditorDocument) -> String? {
        let text = document.text as NSString; guard text.length > 0 else { return nil }; let position = min(document.caretSourceOffset, text.length - 1)
        let characters = CharacterSet.alphanumerics.union(.init(charactersIn: "_?!")); var start = position; var end = position
        while start > 0, let scalar = UnicodeScalar(text.character(at: start - 1)), characters.contains(scalar) { start -= 1 }
        while end < text.length, let scalar = UnicodeScalar(text.character(at: end)), characters.contains(scalar) { end += 1 }
        let value = text.substring(with: NSRange(location: start, length: end - start)); return value.isEmpty ? nil : value
    }
    private func sourceOffset(line: Int, fileURL: URL) -> Int {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8), line > 1 else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).prefix(line - 1).reduce(0) { $0 + ($1 as NSString).length + 1 }
    }
    private func alert(_ error: Error, _ title: String) { let alert = NSAlert(error: error); alert.messageText = title; alert.runModal() }
}

private struct QuickOpenSheet: View {
    @ObservedObject var project: ProjectContext
    let open: (ProjectFileEntry) -> Void
    @State private var query = ""
    private var results: [ProjectFileEntry] { FuzzyMatcher.ranked(query, entries: project.fileIndex.entries) }
    var body: some View { VStack(spacing: 10) { TextField("Quick Open", text: $query).textFieldStyle(.roundedBorder); List(results) { entry in Button(entry.relativePath) { open(entry) }.buttonStyle(.plain) } }.padding().frame(width: 540, height: 360) }
}
