import AppKit
import SwiftUI
import Combine

@main struct ScopeApp: App {
    @NSApplicationDelegateAdaptor(ScopeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var session = EditorSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear { applicationDelegate.session = session }
                .sheet(isPresented: $session.quickOpenPresented) {
                    QuickOpenSheet(entries: session.project?.fileIndex.entries ?? [], open: {
                        session.quickOpenPresented = false
                        session.open($0.url)
                    })
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { session.chooseFile() }.keyboardShortcut("o", modifiers: .command)
                Button("Open Last Used") { session.openLastUsed() }.disabled(session.recentFiles.mostRecentFile == nil)
                Menu("Open Recent") { ForEach(session.recentFiles.menuTitles(), id: \.file) { item in Button(item.title) { session.openRecentFile(item.file) } } }.disabled(session.recentFiles.files.isEmpty)
                Button("Open Folder…") { session.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
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

final class ScopeApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var session: EditorSession?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session, session.hasDirtyDocuments else { return .terminateNow }
        session.confirmCloseAll { NSApp.reply(toApplicationShouldTerminate: $0) }
        return .terminateLater
    }
}

@MainActor final class EditorSession: ObservableObject {
    @Published private(set) var documents: [EditorDocument] = []
    @Published private(set) var activeDocument: EditorDocument?
    @Published var project: ProjectContext?
    @Published var quickOpenPresented = false
    let history = NavigationHistory()
    let recentFiles = RecentFileStore()
    private let documentSessionStore: DocumentSessionStore
    private var symbols = SymbolIndex.empty

    init(documentSessionStore: DocumentSessionStore? = nil, restoreSession: Bool = true) {
        self.documentSessionStore = documentSessionStore ?? DocumentSessionStore()
        if restoreSession { restoreDocuments() }
    }

    var hasDirtyDocuments: Bool { documents.contains { $0.isDirty } }

    func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true
        panel.begin { if $0 == .OK, let url = panel.url { self.open(url) } }
    }
    func openLastUsed() { guard let file = recentFiles.mostRecentFile else { return }; openRecentFile(file) }
    func openRecentFile(_ file: RecentFile) {
        do { open(try recentFiles.resolveURL(for: file), replacing: file) }
        catch { recentFiles.remove(file); alert(error, "Couldn’t Open File") }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.begin { if $0 == .OK, let url = panel.url { let project = ProjectContext(rootURL: url); self.project = project; project.buildFileIndex(); self.index(root: url) } }
    }

    func open(_ url: URL, target: Int? = nil, recordRecent: Bool = true, replacing recentFile: RecentFile? = nil) {
        let canonicalURL = url.standardizedFileURL
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == canonicalURL }) {
            activate(existing); existing.navigationTargetSourceOffset = target
            if recordRecent { recentFiles.recordSuccessfulOpen(canonicalURL, replacing: recentFile) }
            return
        }
        do {
            let document = EditorDocument(); try document.load(from: canonicalURL)
            document.navigationTargetSourceOffset = target
            documents.append(document); activeDocument = document; persistDocuments()
            if recordRecent { recentFiles.recordSuccessfulOpen(canonicalURL, replacing: recentFile) }
        } catch {
            if let recentFile { recentFiles.remove(recentFile) }
            alert(error, "Couldn’t Open File")
        }
    }

    func activate(_ document: EditorDocument) {
        guard documents.contains(where: { $0 === document }) else { return }
        activeDocument = document; persistDocuments()
    }
    func close(_ document: EditorDocument) {
        guard documents.contains(where: { $0 === document }) else { return }
        if document.isDirty { confirm(document: document) { self.remove(document) } } else { remove(document) }
    }
    func save() { guard let activeDocument else { return }; do { try activeDocument.save() } catch { alert(error, "Couldn’t Save File") } }
    func quickOpen() { quickOpenPresented = true }

    func goToDefinition() {
        guard let document = activeDocument, let file = document.fileURL, let word = identifier(in: document), let entry = symbols.lookup(word).first else { return }
        let offset = sourceOffset(line: entry.line, fileURL: entry.fileURL)
        history.record(.init(fileURL: file, sourceOffset: document.caretSourceOffset)); history.record(.init(fileURL: entry.fileURL, sourceOffset: offset))
        open(entry.fileURL, target: offset)
    }
    func back() { if let target = history.back() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    func forward() { if let target = history.forward() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    func confirmCloseAll(completion: @escaping (Bool) -> Void) { confirm(documents.filter(\.isDirty), completion: completion) }

    private func remove(_ document: EditorDocument) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if activeDocument === document { activeDocument = documents.indices.contains(index) ? documents[index] : documents.last }
        persistDocuments()
    }
    private func confirm(_ documents: [EditorDocument], completion: @escaping (Bool) -> Void) {
        guard let document = documents.first else { completion(true); return }
        confirm(document: document, then: { self.confirm(Array(documents.dropFirst()), completion: completion) }, cancel: { completion(false) })
    }
    private func confirm(document: EditorDocument, then: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
        let alert = NSAlert(); alert.messageText = "Do you want to save the changes you made to \(document.windowTitle)?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Don’t Save"); alert.addButton(withTitle: "Cancel")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { do { try document.save(); then() } catch { self.alert(error, "Couldn’t Save File"); cancel() } }
            else if response == .alertSecondButtonReturn { then() } else { cancel() }
        }
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }
    private func restoreDocuments() {
        let saved = documentSessionStore.load()
        for entry in saved.documents {
            guard let url = try? DocumentSessionStore.resolveURL(for: entry) else { continue }
            let document = EditorDocument(id: entry.id)
            do { try document.load(from: url) } catch { continue }
            documents.append(document)
        }
        activeDocument = documents.first(where: { $0.id == saved.activeDocumentID }) ?? documents.first
        persistDocuments()
    }
    private func persistDocuments() {
        let entries = documents.compactMap { document -> RestorableDocument? in
            guard let url = document.fileURL, let entry = DocumentSessionStore.document(for: url) else { return nil }
            return RestorableDocument(id: document.id, bookmarkData: entry.bookmarkData, displayPath: entry.displayPath)
        }
        documentSessionStore.save(.init(documents: entries, activeDocumentID: activeDocument?.id))
    }
    private func index(root: URL) { Task.detached(priority: .userInitiated) { let result = CtagsRunner.buildIndex(rootURL: root); await MainActor.run { self.symbols = result } } }
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
    let entries: [ProjectFileEntry]; let open: (ProjectFileEntry) -> Void
    @State private var query = ""
    private var results: [ProjectFileEntry] { FuzzyMatcher.ranked(query, entries: entries) }
    var body: some View { VStack(spacing: 10) { TextField("Quick Open", text: $query).textFieldStyle(.roundedBorder); List(results) { entry in Button(entry.relativePath) { open(entry) }.buttonStyle(.plain) } }.padding().frame(width: 540, height: 360) }
}
