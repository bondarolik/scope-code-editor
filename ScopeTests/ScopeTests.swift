import XCTest
@testable import Scope

final class ScopeTests: XCTestCase {
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
