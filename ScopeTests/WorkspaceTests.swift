import AppKit
import SwiftUI
import XCTest
@testable import Scope

@MainActor
final class WorkspaceTests: XCTestCase {
    private enum BookmarkError: Error { case unavailable }

    func testRestoresDocumentOrderActiveDocumentAndProject() throws {
        let root = try temporaryFolder()
        let first = try file("first.rb", in: root)
        let second = try file("second.rb", in: root)
        let third = try file("third.rb", in: root)
        let store = sessionStore()
        let bookmarks = pathBookmarks()
        let original = EditorSession(documentSessionStore: store, bookmarks: bookmarks, restoreSession: false)
        original.openProject(root)
        for url in [first, second, third] { original.open(url, recordRecent: false) }
        original.activate(original.documents[1])
        let savedIDs = original.documents.map(\.id)

        let restored = EditorSession(documentSessionStore: store, bookmarks: bookmarks)

        XCTAssertEqual(restored.documents.map(\.id), savedIDs)
        XCTAssertEqual(restored.documents.compactMap { $0.fileURL?.path }, [first.path, second.path, third.path])
        XCTAssertEqual(restored.activeDocument?.id, savedIDs[1])
        XCTAssertEqual(restored.project?.rootURL.path, root.path)
    }

    func testTemporaryResolutionFailurePreservesEntriesAndPreferredDocumentOnWrite() throws {
        let root = try temporaryFolder()
        let unavailable = try file("unavailable.rb", in: root)
        let second = try file("second.rb", in: root)
        let third = try file("third.rb", in: root)
        let store = sessionStore()
        let original = EditorSession(documentSessionStore: store, bookmarks: pathBookmarks(), restoreSession: false)
        for url in [unavailable, second, third] { original.open(url, recordRecent: false) }
        original.activate(original.documents[0])
        let saved = store.load()

        var temporarilyFailing = pathBookmarks()
        let resolve = temporarilyFailing.resolve
        temporarilyFailing.resolve = { data in
            let bookmark = try resolve(data)
            guard bookmark.url.path != unavailable.path else { throw BookmarkError.unavailable }
            return bookmark
        }
        let partial = EditorSession(documentSessionStore: store, bookmarks: temporarilyFailing)
        XCTAssertEqual(partial.documents.map(\.id), Array(saved.documents.dropFirst()).map(\.id))
        XCTAssertEqual(partial.activeDocument?.id, saved.documents[1].id)
        partial.close(try XCTUnwrap(partial.documents.last))

        XCTAssertEqual(store.load().documents, Array(saved.documents.prefix(2)))
        XCTAssertEqual(store.load().activeDocumentID, saved.activeDocumentID)
        let nextLaunch = EditorSession(documentSessionStore: store, bookmarks: pathBookmarks())
        XCTAssertEqual(nextLaunch.documents.map(\.id), Array(saved.documents.prefix(2)).map(\.id))
        XCTAssertEqual(nextLaunch.activeDocument?.id, saved.activeDocumentID)
    }

    func testMissingFileRetainsOriginalSlotWhenExplicitlyReopened() throws {
        let root = try temporaryFolder()
        let first = try file("first.rb", in: root)
        let second = try file("second.rb", in: root)
        let store = sessionStore()
        let bookmarks = pathBookmarks()
        let original = EditorSession(documentSessionStore: store, bookmarks: bookmarks, restoreSession: false)
        original.open(first, recordRecent: false)
        original.open(second, recordRecent: false)
        let saved = store.load()
        try FileManager.default.removeItem(at: first)

        let restored = EditorSession(documentSessionStore: store, bookmarks: bookmarks)
        XCTAssertEqual(restored.documents.map(\.id), [saved.documents[1].id])
        XCTAssertEqual(store.load(), saved)
        _ = try file("first.rb", in: root)
        restored.open(first, recordRecent: false)

        XCTAssertEqual(restored.documents.map(\.id), saved.documents.map(\.id))
        XCTAssertEqual(restored.activeDocument?.id, saved.documents[0].id)
    }

    func testRefreshesStaleBookmarkOnlyAfterReadableResolutionAndKeepsOriginalOnFailure() throws {
        let root = try temporaryFolder()
        let first = try file("first.rb", in: root)
        let second = try file("second.rb", in: root)
        let missing = root.appendingPathComponent("missing.rb")
        let previous = [first, second, missing].map {
            RestorableDocument(id: UUID(), bookmarkData: Data($0.path.utf8), displayPath: $0.path)
        }
        let store = sessionStore()
        store.save(.init(documents: previous, activeDocumentID: previous[0].id))
        let bookmarks = WorkspaceBookmarks(
            make: { url in
                guard url.path == first.path else { throw BookmarkError.unavailable }
                return Data("refreshed".utf8)
            },
            resolve: { data in
                (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), true)
            }
        )

        let session = EditorSession(documentSessionStore: store, bookmarks: bookmarks)

        XCTAssertEqual(session.documents.map(\.id), Array(previous.prefix(2)).map(\.id))
        let stored = store.load().documents
        XCTAssertEqual(stored[0].bookmarkData, Data("refreshed".utf8))
        XCTAssertEqual(Array(stored.dropFirst()), Array(previous.dropFirst()))
    }

    func testExplicitCloseRemovesPersistedEntryAndSelectsAdjacentTab() throws {
        let root = try temporaryFolder()
        let first = try file("first.rb", in: root)
        let second = try file("second.rb", in: root)
        let store = sessionStore()
        let bookmarks = pathBookmarks()
        let session = EditorSession(documentSessionStore: store, bookmarks: bookmarks, restoreSession: false)
        session.open(first, recordRecent: false)
        session.open(second, recordRecent: false)
        let firstID = session.documents[0].id

        session.close(try XCTUnwrap(session.activeDocument))

        XCTAssertEqual(store.load().documents.map(\.id), [firstID])
        XCTAssertEqual(store.load().activeDocumentID, firstID)
        let restored = EditorSession(documentSessionStore: store, bookmarks: bookmarks)
        XCTAssertEqual(restored.activeDocument?.id, firstID)
    }

    func testProjectScanIncludesEmptyAndNestedDirectoriesAndIndexesOnlyFiles() throws {
        let root = try temporaryFolder()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        _ = try file("lib/nested/code.rb", in: root)
        _ = try file("README.md", in: root)

        let scan = try ProjectFileIndexer.scan(rootURL: root)

        XCTAssertEqual(scan.treeRoots.map(\.name), ["empty", "lib", "README.md"])
        let empty = try XCTUnwrap(scan.treeRoots.first)
        XCTAssertTrue(empty.isDirectory)
        XCTAssertTrue(empty.children.isEmpty)
        XCTAssertEqual(scan.treeRoots[1].children.first?.children.map(\.name), ["code.rb"])
        XCTAssertEqual(scan.fileIndex.entries.map(\.relativePath), ["lib/nested/code.rb", "README.md"])
    }

    func testProjectScanKeepsRootRelativeIgnoreRules() throws {
        let root = try temporaryFolder()
        for path in [".git/config", "vendor/bundle/dependency.rb", "public/assets/app.js", "node_modules/index.js", ".DS_Store", "src/.DS_Store", "src/tmp/keep.rb", "logfile"] {
            _ = try file(path, in: root)
        }

        let scan = try ProjectFileIndexer.scan(rootURL: root)

        XCTAssertEqual(scan.treeRoots.map(\.name), ["public", "src", "vendor", "logfile"])
        XCTAssertEqual(scan.fileIndex.entries.map(\.relativePath), ["logfile", "src/tmp/keep.rb"])
    }

    func testMissingProjectPublishesScanFailure() async throws {
        let folder = try temporaryFolder().appendingPathComponent("missing")
        let project = ProjectContext(rootURL: folder)

        await project.buildFileIndex().value

        guard case .failed = project.state else { return XCTFail("Expected an explicit scan failure") }
        XCTAssertTrue(project.fileIndex.entries.isEmpty)
    }

    func testOlderScanCannotReplaceNewerProjectScanResult() async throws {
        let root = try temporaryFolder()
        let project = ProjectContext(rootURL: root)
        let allowOldScanToFinish = DispatchSemaphore(value: 0)
        let previous = project.buildFileIndex { url in
            _ = allowOldScanToFinish.wait(timeout: .now() + 5)
            return selfContainedScan("old.rb", at: url)
        }
        let latest = project.buildFileIndex { selfContainedScan("new.rb", at: $0) }
        await latest.value
        allowOldScanToFinish.signal()
        await previous.value

        XCTAssertEqual(project.fileIndex.entries.map(\.relativePath), ["new.rb"])
    }

    func testCanceledProjectScanDoesNotPublishAfterProjectChanges() async throws {
        let project = ProjectContext(rootURL: try temporaryFolder())
        let allowScanToFinish = DispatchSemaphore(value: 0)
        let scan = project.buildFileIndex { url in
            _ = allowScanToFinish.wait(timeout: .now() + 5)
            return selfContainedScan("old.rb", at: url)
        }
        project.cancelScan()
        allowScanToFinish.signal()
        await scan.value

        XCTAssertTrue(project.fileIndex.entries.isEmpty)
        guard case .scanning = project.state else { return XCTFail("Canceled scan published a result") }
    }

    func testWindowCloseGateRejectsDuplicateRequestsAndClearsAfterCancel() {
        var gate = WorkspaceCloseGate()

        XCTAssertTrue(gate.begin(.window))
        XCTAssertFalse(gate.begin(.window))
        XCTAssertFalse(gate.begin(.quit))
        gate.finish(.window, approved: false)
        XCTAssertFalse(gate.windowCloseApproved)
        XCTAssertNil(gate.pending)

        XCTAssertTrue(gate.begin(.quit))
        XCTAssertFalse(gate.begin(.window))
        gate.finish(.quit, approved: false)
        XCTAssertTrue(gate.begin(.window))
        gate.finish(.window, approved: true)
        XCTAssertTrue(gate.windowCloseApproved)
        XCTAssertFalse(gate.begin(.quit))
        gate.resetWindowApproval()
        XCTAssertTrue(gate.begin(.quit))
    }

    func testEmptyDocumentPermitsInsertionAtStart() {
        let presentation = FoldedTextProjection(source: "", collapsedRanges: [])
        let insertion = NSRange(location: 0, length: 0)
        XCTAssertEqual(presentation.editableSourceRange(forPresentationRange: insertion), insertion)
        XCTAssertNil(presentation.editableSourceRange(forPresentationRange: NSRange(location: 1, length: 0)))
    }

    func testRefreshingUnchangedProjectionPreservesNativeSelection() {
        let view = makeTextView()
        view.applyProjection(source: "some selected text", collapsedRanges: [])
        let selection = NSRange(location: 5, length: 8)
        view.setSelectedRange(selection)

        view.applyProjection(source: "some selected text", collapsedRanges: [])

        XCTAssertEqual(view.selectedRange(), selection)
    }

    func testRetainedNativeEditorsHaveIndependentUndoAndRedo() throws {
        let (firstView, first, firstCoordinator) = makeEditor("first")
        let (secondView, second, secondCoordinator) = makeEditor("second")
        let window = NSWindow(contentRect: firstView.frame, styleMask: .titled, backing: .buffered, defer: false)
        window.contentView?.addSubview(firstView)
        window.contentView?.addSubview(secondView)
        defer { withExtendedLifetime(firstCoordinator) {} }
        let firstUndo = try XCTUnwrap(firstView.sourceUndoManager)
        defer { withExtendedLifetime(secondCoordinator) {} }
        let secondUndo = try XCTUnwrap(secondView.sourceUndoManager)
        firstUndo.groupsByEvent = false
        secondUndo.groupsByEvent = false
        XCTAssertTrue(window.makeFirstResponder(firstView))
        firstUndo.beginUndoGrouping()
        firstView.setSelectedRange(NSRange(location: 5, length: 0))
        firstView.insertText("!", replacementRange: firstView.selectedRange())
        firstUndo.endUndoGrouping()
        XCTAssertTrue(window.makeFirstResponder(secondView))
        secondUndo.beginUndoGrouping()
        secondView.setSelectedRange(NSRange(location: 6, length: 0))
        secondView.insertText("?", replacementRange: secondView.selectedRange())
        secondUndo.endUndoGrouping()

        XCTAssertEqual(firstView.string, "first!")
        XCTAssertEqual(secondView.string, "second?")
        XCTAssertEqual(first.text, "first!")
        XCTAssertEqual(second.text, "second?")
        XCTAssertTrue(window.makeFirstResponder(firstView))
        let undoItem = NSMenuItem(title: "Undo", action: #selector(CodeTextView.undoSourceEdit(_:)), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(CodeTextView.redoSourceEdit(_:)), keyEquivalent: "Z")
        XCTAssertTrue(firstView.validateMenuItem(undoItem))
        XCTAssertFalse(firstView.validateMenuItem(redoItem))
        XCTAssertTrue(window.firstResponder?.tryToPerform(#selector(CodeTextView.undoSourceEdit(_:)), with: nil) == true)
        XCTAssertEqual(firstView.string, "first")
        XCTAssertEqual(first.text, "first")
        XCTAssertEqual(second.text, "second?")
        XCTAssertTrue(firstView.validateMenuItem(redoItem))
        XCTAssertTrue(window.firstResponder?.tryToPerform(#selector(CodeTextView.redoSourceEdit(_:)), with: nil) == true)
        XCTAssertEqual(first.text, "first!")
    }

    func testUndoAndRedoAcrossEditsAndFoldChanges() throws {
        let source = "def hello\n  puts :hidden\nend\nafter"
        let fold = FoldRange(startLine: 1, endLine: 3, closingToken: "end")
        let (view, document, coordinator) = makeEditor(source)
        let window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        XCTAssertTrue(window.makeFirstResponder(view))
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false

        edit(view, with: "!", at: NSRange(location: source.utf16.count, length: 0), undo: undo)
        view.applyProjection(source: document.text, collapsedRanges: [fold])
        let summary = try XCTUnwrap(view.foldedSummaries.first)
        let before = NSRange(location: summary.presentationRange.location - 5, length: 5)
        edit(view, with: "goodbye", at: before, undo: undo)
        XCTAssertEqual(document.text, "def goodbye\n  puts :hidden\nend\nafter!")

        view.applyProjection(source: document.text, collapsedRanges: [fold])
        let after = try XCTUnwrap(view.foldedSummaries.first).presentationRange.upperBound
        edit(view, with: "", at: NSRange(location: after, length: 1), undo: undo)
        XCTAssertEqual(document.text, "def goodbye\n  puts :hidden\nend\nfter!")
        view.applyProjection(source: document.text, collapsedRanges: [fold])

        undo.undo()
        XCTAssertEqual(document.text, "def goodbye\n  puts :hidden\nend\nafter!")
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "a")
        undo.undo()
        XCTAssertEqual(document.text, source + "!")
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "hello")
        undo.undo()
        XCTAssertEqual(document.text, source)
        XCTAssertFalse(undo.canUndo)

        view.applyProjection(source: document.text, collapsedRanges: [fold])
        view.applyProjection(source: document.text, collapsedRanges: [])
        undo.redo()
        XCTAssertEqual(document.text, source + "!")
        view.applyProjection(source: document.text, collapsedRanges: [fold])
        undo.redo()
        XCTAssertEqual(document.text, "def goodbye\n  puts :hidden\nend\nafter!")
        undo.redo()
        XCTAssertEqual(document.text, "def goodbye\n  puts :hidden\nend\nfter!")
        XCTAssertEqual(view.string, document.text)
        XCTAssertEqual(view.selectedRange(), NSRange(location: document.text.utf16.count - "fter!".utf16.count, length: 0))
        XCTAssertEqual(document.caretSourceOffset, view.selectedRange().location)
        XCTAssertFalse(undo.canRedo)
    }

    func testEditAcrossFoldSummaryCannotRemoveHiddenSourceOrHistory() throws {
        let source = "def hello\n  puts :hidden\nend\nafter"
        let (view, document, coordinator) = makeEditor(source)
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false
        edit(view, with: "!", at: NSRange(location: source.utf16.count, length: 0), undo: undo)
        view.applyProjection(source: document.text, collapsedRanges: [FoldRange(startLine: 1, endLine: 3, closingToken: "end")])
        let summary = try XCTUnwrap(view.foldedSummaries.first)
        view.setSelectedRange(summary.presentationRange)
        view.insertText("replacement", replacementRange: summary.presentationRange)

        XCTAssertEqual(document.text, source + "!")
        XCTAssertFalse(view.foldedSummaries.isEmpty)
        undo.undo()
        XCTAssertEqual(document.text, source)
        XCTAssertFalse(undo.canUndo)
    }

    func testUndoAndRedoPreserveUTF16AndDirtyStateAcrossFolding() throws {
        let root = try temporaryFolder()
        let url = try file("unicode.rb", in: root)
        let source = "def hello\n  puts \"🔒\"\nend\n🧑🏽‍💻 café"
        try source.write(to: url, atomically: true, encoding: .utf8)
        let document = EditorDocument()
        try document.load(from: url)
        let (view, _, coordinator) = makeEditor(source, document: document)
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false
        let fold = FoldRange(startLine: 1, endLine: 3, closingToken: "end")
        view.applyProjection(source: source, collapsedRanges: [fold])

        let range = (view.string as NSString).range(of: "café")
        edit(view, with: "cafe\u{301} 👋", at: range, undo: undo)
        let updated = "def hello\n  puts \"🔒\"\nend\n🧑🏽‍💻 cafe\u{301} 👋"
        XCTAssertEqual(Array(document.text.utf16), Array(updated.utf16))
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(view.selectedRange().location, updated.utf16.count)

        view.applyProjection(source: document.text, collapsedRanges: [fold])
        undo.undo()
        XCTAssertEqual(Array(document.text.utf16), Array(source.utf16))
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(view.selectedRange(), (source as NSString).range(of: "café"))

        undo.redo()
        XCTAssertEqual(Array(document.text.utf16), Array(updated.utf16))
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.caretSourceOffset, updated.utf16.count)

        try document.save()
        undo.undo()
        XCTAssertTrue(document.isDirty)
        undo.redo()
        XCTAssertFalse(document.isDirty)
    }

    func testCanonicallyEquivalentReplacementIsUndoable() throws {
        let source = "café"
        let url = try file("normalization.txt", in: temporaryFolder())
        try source.write(to: url, atomically: true, encoding: .utf8)
        let document = EditorDocument()
        try document.load(from: url)
        let (view, _, coordinator) = makeEditor(source, document: document)
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false
        edit(view, with: "e\u{301}", at: NSRange(location: 3, length: 1), undo: undo)

        XCTAssertEqual(Array(document.text.utf16), Array("cafe\u{301}".utf16))
        XCTAssertEqual(Array(view.string.utf16), Array(document.text.utf16))
        XCTAssertTrue(document.isDirty)
        undo.undo()
        XCTAssertEqual(Array(document.text.utf16), Array(source.utf16))
        XCTAssertFalse(document.isDirty)
        undo.redo()
        XCTAssertEqual(Array(document.text.utf16), Array("cafe\u{301}".utf16))
    }

    func testMultiRangeReplacementAcrossFoldUndoesAsOneEdit() throws {
        let source = "def hello\n  puts :hidden\nend\nafter"
        let (view, document, coordinator) = makeEditor(source)
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false
        view.applyProjection(source: source, collapsedRanges: [FoldRange(startLine: 1, endLine: 3, closingToken: "end")])
        let presented = view.string as NSString
        let ranges = [presented.range(of: "hello"), presented.range(of: "after")]
        let replacements = ["greeting", ""]
        undo.beginUndoGrouping()
        XCTAssertTrue(view.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements))
        for (range, replacement) in zip(ranges, replacements).reversed() {
            view.textStorage?.replaceCharacters(in: range, with: replacement)
        }
        view.didChangeText()
        undo.endUndoGrouping()

        XCTAssertEqual(document.text, "def greeting\n  puts :hidden\nend\n")
        undo.undo()
        XCTAssertEqual(document.text, source)
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(document.text, "def greeting\n  puts :hidden\nend\n")
    }

    func testMarkedTextCommitsAsOneCanonicalEditAfterFold() throws {
        let source = "def hello\n  puts :hidden\nend\nafter"
        let (view, document, coordinator) = makeEditor(source)
        defer { withExtendedLifetime(coordinator) {} }
        let undo = try XCTUnwrap(view.sourceUndoManager)
        undo.groupsByEvent = false
        view.applyProjection(source: source, collapsedRanges: [FoldRange(startLine: 1, endLine: 3, closingToken: "end")])
        let insertion = NSRange(location: view.string.utf16.count, length: 0)
        view.setSelectedRange(insertion)
        undo.beginUndoGrouping()
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: insertion)
        XCTAssertEqual(document.text, source)
        XCTAssertTrue(view.hasMarkedText())
        view.insertText("你", replacementRange: view.markedRange())
        undo.endUndoGrouping()

        XCTAssertEqual(document.text, source + "你")
        XCTAssertFalse(view.hasMarkedText())
        undo.undo()
        XCTAssertEqual(document.text, source)
        undo.redo()
        XCTAssertEqual(document.text, source + "你")
    }

    private func edit(_ view: CodeTextView, with replacement: String, at range: NSRange, undo: UndoManager) {
        undo.beginUndoGrouping()
        view.setSelectedRange(range)
        view.insertText(replacement, replacementRange: range)
        undo.endUndoGrouping()
    }

    private func makeEditor(_ source: String, document existingDocument: EditorDocument? = nil) -> (CodeTextView, EditorDocument, NativeTextEditor.Coordinator) {
        let document = existingDocument ?? EditorDocument()
        document.updateText(source)
        let coordinator = NativeTextEditor.Coordinator(
            text: Binding(get: { document.text }, set: document.updateText),
            status: .constant(EditorStatus()),
            language: nil,
            indentationWidth: 2,
            caretSourceOffset: Binding(get: { document.caretSourceOffset }, set: document.updateCaretSourceOffset),
            navigationTarget: .constant(nil)
        )
        let view = makeTextView()
        view.applyProjection(source: source, collapsedRanges: [])
        coordinator.attach(to: view)
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        return (view, document, coordinator)
    }

    private func pathBookmarks() -> WorkspaceBookmarks {
        WorkspaceBookmarks(
            make: { Data($0.path.utf8) },
            resolve: { (URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)), false) }
        )
    }

    private func makeTextView() -> CodeTextView {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 200, height: 100))
        layout.textContainer = container
        return CodeTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), textContainer: container, indentationWidth: 2)
    }

    private func sessionStore() -> DocumentSessionStore {
        let name = "ScopeTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return DocumentSessionStore(defaults: defaults)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func file(_ path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "contents".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private func selfContainedScan(_ path: String, at url: URL) -> ProjectScan {
    let entry = ProjectFileEntry(url: url.appendingPathComponent(path), relativePath: path)
    return ProjectScan(fileIndex: ProjectFileIndex(entries: [entry]), treeRoots: [])
}
