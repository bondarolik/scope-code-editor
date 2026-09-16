import AppKit
import SwiftUI
import Combine

@main struct ScopeApp: App {
    @NSApplicationDelegateAdaptor(ScopeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var session = EditorSession()
    var body: some Scene {
        WindowGroup { ContentView(document: session.document, project: session.project, openFile: { session.open($0) }).frame(minWidth: 600, minHeight: 400).sheet(isPresented: $session.quickOpenPresented) { QuickOpenSheet(entries: session.project?.fileIndex.entries ?? [], open: { session.quickOpenPresented = false; session.open($0.url) }) } }
        .commands { CommandGroup(after: .newItem) {
            Button("Open…") { session.chooseFile() }.keyboardShortcut("o", modifiers: .command)
            Button("Open Last Used") { session.openLastUsed() }.disabled(session.recentFiles.mostRecentFile == nil)
            Menu("Open Recent") {
                ForEach(session.recentFiles.menuTitles(), id: \.file) { item in
                    Button(item.title) { session.openRecentFile(item.file) }
                }
            }
            .disabled(session.recentFiles.files.isEmpty)
            Button("Open Folder…") { session.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Quick Open") { session.quickOpen() }.keyboardShortcut("p", modifiers: .command).disabled(session.project == nil)
            Button("Go to Definition") { session.goToDefinition() }.keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(session.project == nil)
            Button("Navigate Back") { session.back() }.keyboardShortcut(.leftArrow, modifiers: [.command, .control]).disabled(!session.history.canGoBack)
            Button("Navigate Forward") { session.forward() }.keyboardShortcut(.rightArrow, modifiers: [.command, .control]).disabled(!session.history.canGoForward)
            Divider(); Button("Save") { session.save() }.keyboardShortcut("s", modifiers: .command).disabled(session.document.fileURL == nil)
        } }
    }
}

final class ScopeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor final class EditorSession: ObservableObject {
    let document = EditorDocument(); let history = NavigationHistory(); let recentFiles = RecentFileStore(); @Published var project: ProjectContext?; @Published var quickOpenPresented = false; private var symbols = SymbolIndex.empty
    func chooseFile() { let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.begin { if $0 == .OK, let url = panel.url { self.open(url, recordRecent: true) } } }
    func openLastUsed() { guard let file = recentFiles.mostRecentFile else { return }; openRecentFile(file) }
    func openRecentFile(_ file: RecentFile) { do { open(try recentFiles.resolveURL(for: file), recordRecent: true, replacing: file) } catch { recentFiles.remove(file); alert(error, "Couldn’t Open File") } }
    func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.begin { if $0 == .OK, let url = panel.url { let project = ProjectContext(rootURL: url); self.project = project; project.buildFileIndex(); self.index(root: url) } } }
    func open(_ url: URL, target: Int? = nil, recordRecent: Bool = true, replacing recentFile: RecentFile? = nil) { if document.isDirty { confirm { self.load(url, target: target, recordRecent: recordRecent, replacing: recentFile) } } else { load(url, target: target, recordRecent: recordRecent, replacing: recentFile) } }
    private func load(_ url: URL, target: Int? = nil, recordRecent: Bool, replacing recentFile: RecentFile?) { do { let loaded = try document.prepareLoad(from: url); document.activate(loaded); document.navigationTargetSourceOffset = target; if recordRecent { recentFiles.recordSuccessfulOpen(url, replacing: recentFile) } } catch { if let recentFile { recentFiles.remove(recentFile) }; alert(error, "Couldn’t Open File") } }
    func save() { do { try document.save() } catch { alert(error, "Couldn’t Save File") } }
    func quickOpen() { quickOpenPresented = true }
    func goToDefinition() { guard let file = document.fileURL else { return }; let location = NavigationLocation(fileURL: file, sourceOffset: document.caretSourceOffset); guard let word = identifier() else { return }; let results = symbols.lookup(word); if let entry = results.first { let offset = sourceOffset(line: entry.line, fileURL: entry.fileURL); history.record(location); history.record(.init(fileURL: entry.fileURL, sourceOffset: offset)); open(entry.fileURL, target: offset) } }
    func back() { if let target = history.back() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    func forward() { if let target = history.forward() { open(target.fileURL, target: target.sourceOffset, recordRecent: false) } }
    private func index(root: URL) { Task.detached(priority: .userInitiated) { let result = CtagsRunner.buildIndex(rootURL: root); await MainActor.run { self.symbols = result } } }
    private func identifier() -> String? { let ns = document.text as NSString; let i = min(document.caretSourceOffset, max(0, ns.length - 1)); guard ns.length > 0 else { return nil }; let set = CharacterSet.alphanumerics.union(.init(charactersIn: "_?!")); var a = i; var b = i; while a > 0, let s = UnicodeScalar(ns.character(at: a - 1)), set.contains(s) { a -= 1 }; while b < ns.length, let s = UnicodeScalar(ns.character(at: b)), set.contains(s) { b += 1 }; let value = ns.substring(with: .init(location: a, length: b - a)); return value.isEmpty ? nil : value }
    private func sourceOffset(line: Int, fileURL: URL) -> Int { guard let text = try? String(contentsOf: fileURL, encoding: .utf8), line > 1 else { return 0 }; var offset = 0; for (index, part) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() { if index >= line - 1 { break }; offset += (part as NSString).length + 1 }; return offset }
    private func confirm(_ then: @escaping () -> Void) { let a = NSAlert(); a.messageText = "Do you want to save the changes you made?"; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Don’t Save"); a.addButton(withTitle: "Cancel"); let handle: (NSApplication.ModalResponse) -> Void = { r in if r == .alertFirstButtonReturn { do { try self.document.save(); then() } catch { self.alert(error, "Couldn’t Save File") } } else if r == .alertSecondButtonReturn { then() } }; if let w = NSApp.keyWindow { a.beginSheetModal(for: w, completionHandler: handle) } else { handle(a.runModal()) } }
    private func alert(_ error: Error, _ title: String) { let a = NSAlert(error: error); a.messageText = title; a.runModal() }
}

private struct QuickOpenSheet: View {
    let entries: [ProjectFileEntry]; let open: (ProjectFileEntry) -> Void
    @State private var query = ""; @State private var selected = 0
    private var results: [ProjectFileEntry] { FuzzyMatcher.ranked(query, entries: entries) }
    var body: some View { VStack(spacing: 10) { TextField("Quick Open", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { _ in selected = 0 }; List(results) { entry in Button(entry.relativePath) { open(entry) }.buttonStyle(.plain) } }.padding().frame(width: 540, height: 360) }
}
