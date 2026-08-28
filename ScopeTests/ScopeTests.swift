import XCTest
@testable import Scope

final class ScopeTests: XCTestCase {
    func testRubySyntaxDetectionAndParsing() {
        let highlighter = RubySyntaxHighlighter()
        XCTAssertEqual(LanguageDetector.language(for: URL(fileURLWithPath: "/tmp/example.rb")), .ruby)
        XCTAssertNil(LanguageDetector.language(for: URL(fileURLWithPath: "/tmp/example.swift")))
        XCTAssertTrue(highlighter.canParse("class Example\n  def run\n  end\nend"))
        XCTAssertTrue(highlighter.canParse("def incomplete("))

        let spans = SyntaxHighlighter.spans(
            for: .ruby,
            source: "# comment\nclass Example\n  def run\n    :symbol\n  end\nend"
        )
        XCTAssertTrue(spans.contains { $0.category == .comment })
        XCTAssertTrue(spans.contains { $0.category == .keyword })
        XCTAssertTrue(spans.contains { $0.category == .symbol })
        XCTAssertTrue(SyntaxHighlighter.spans(for: nil, source: "plain text").isEmpty)
        XCTAssertNil(RubySyntaxHighlighter.category(for: "unknown.capture"))
    }

    func testStaleHighlightRequestsAreRejected() {
        var tracker = HighlightRequestTracker()
        let firstRequest = tracker.makeRequest(for: "before")
        let latestRequest = tracker.makeRequest(for: "after")

        XCTAssertFalse(tracker.accepts(firstRequest, for: "after"))
        XCTAssertTrue(tracker.accepts(latestRequest, for: "after"))
    }

    func testIndentationDetection() {
        XCTAssertEqual(IndentationDetector.width(in: "class Example\n  def call\n    true\n  end\nend"), 2)
        XCTAssertEqual(IndentationDetector.width(in: "root\n    child\n        nested"), 4)
        XCTAssertEqual(IndentationDetector.width(in: "root\n        child\n                nested"), 8)
        XCTAssertEqual(IndentationDetector.width(in: "root\n    \n    child\n        nested"), 4)
        XCTAssertEqual(IndentationDetector.width(in: "root\nchild"), 2)

        let tabs = "root\n\tchild\n\t\tnested"
        XCTAssertEqual(IndentationDetector.width(in: tabs), 2)
        XCTAssertEqual(tabs, "root\n\tchild\n\t\tnested")
    }

    func testEditorPosition() {
        XCTAssertEqual(EditorPosition.at(utf16Offset: 0, in: ""), .beginning)
        XCTAssertEqual(EditorPosition.at(utf16Offset: 0, in: "one\ntwo"), EditorPosition(line: 1, column: 1))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 3, in: "one\ntwo"), EditorPosition(line: 1, column: 4))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 4, in: "one\ntwo"), EditorPosition(line: 2, column: 1))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 4, in: "one\n\ntwo"), EditorPosition(line: 2, column: 1))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 5, in: "one\n\ntwo"), EditorPosition(line: 3, column: 1))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 3, in: "a😀b"), EditorPosition(line: 1, column: 3))
        XCTAssertEqual(EditorPosition.at(utf16Offset: 2, in: "a😀b"), EditorPosition(line: 1, column: 2))
    }

    func testLineNumberMetrics() {
        XCTAssertEqual(LineNumberMetrics.lineCount(in: ""), 1)
        XCTAssertEqual(LineNumberMetrics.lineCount(in: "one\ntwo\nthree"), 3)
        XCTAssertGreaterThan(LineNumberMetrics.gutterWidth(forLineCount: 1, font: .systemFont(ofSize: 11)), 0)
        XCTAssertGreaterThan(LineNumberMetrics.gutterWidth(forLineCount: 1_000, font: .systemFont(ofSize: 11)), LineNumberMetrics.gutterWidth(forLineCount: 1, font: .systemFont(ofSize: 11)))
    }
    func testLoadingUTF8TextStartsClean() throws {
        let url = try makeTemporaryFile(contents: "let scope = true")
        let document = EditorDocument()

        try document.load(from: url)

        XCTAssertEqual(document.fileURL, url)
        XCTAssertEqual(document.text, "let scope = true")
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.windowTitle, url.lastPathComponent)
    }

    func testEditingMarksDocumentDirtyAndSavingResetsState() throws {
        let url = try makeTemporaryFile(contents: "before")
        let document = EditorDocument()
        try document.load(from: url)

        document.updateText("after")
        XCTAssertTrue(document.isDirty)

        try document.save()

        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "after")
    }

    func testLoadingAndSavingPreservesExistingTabs() throws {
        let contents = "root\n\tchild\n\t\tnested\n"
        let url = try makeTemporaryFile(contents: contents)
        let document = EditorDocument()

        try document.load(from: url)
        try document.save()

        XCTAssertEqual(document.text, contents)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), contents)
        XCTAssertEqual(document.indentationWidth, 2)
    }

    func testLoadingNonUTF8DataThrowsAnError() throws {
        let url = try makeTemporaryFile(data: Data([0xFF, 0xFE]))
        let document = EditorDocument()

        XCTAssertThrowsError(try document.load(from: url)) { error in
            XCTAssertEqual(error as? EditorDocumentError, .unsupportedTextEncoding)
        }
    }

    func testSavingWithoutAnOpenFileThrowsAnError() {
        let document = EditorDocument()

        XCTAssertThrowsError(try document.save()) { error in
            XCTAssertEqual(error as? EditorDocumentError, .noOpenFile)
        }
    }

    private func makeTemporaryFile(contents: String) throws -> URL {
        try makeTemporaryFile(data: Data(contents.utf8))
    }

    private func makeTemporaryFile(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
