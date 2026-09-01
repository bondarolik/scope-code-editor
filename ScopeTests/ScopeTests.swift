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

    func testRubyStructuralFoldRanges() {
        let highlighter = RubySyntaxHighlighter()

        XCTAssertEqual(
            highlighter.foldRanges(in: "def example\n  foo\nend"),
            [FoldRange(startLine: 1, endLine: 3)]
        )
        XCTAssertEqual(
            highlighter.foldRanges(in: "def foo; true; end"),
            []
        )

        let nested = highlighter.foldRanges(in: """
        class Example
          def foo
            items.each do |item|
              process(item)
            end
          end
        end
        """)
        XCTAssertEqual(
            Set(nested),
            Set([
                FoldRange(startLine: 1, endLine: 7),
                FoldRange(startLine: 2, endLine: 6),
                FoldRange(startLine: 3, endLine: 5)
            ])
        )
        XCTAssertTrue(highlighter.foldRanges(in: "def foo\n  something").isEmpty)
        XCTAssertTrue(SyntaxHighlighter.analyze(language: nil, source: "plain text").foldRanges.isEmpty)
    }

    func testFoldStateAndPresentationRanges() {
        let range = FoldRange(startLine: 1, endLine: 3)
        let source = "def example\n  foo\nend\nafter\n"
        XCTAssertEqual(range.hiddenCharacterRange(in: source), NSRange(location: 12, length: 10))
        XCTAssertEqual(range.startCharacterLocation(in: source), 0)

        var state = FoldState()
        state.toggle(range)
        XCTAssertEqual(state.collapsedRanges, [range])
        state.retainOnly([])
        XCTAssertTrue(state.collapsedRanges.isEmpty)
        state.toggle(range)
        state.invalidate()
        XCTAssertTrue(state.collapsedRanges.isEmpty)
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
        let font = EditorConfiguration.Gutter.font
        let singleDigitWidth = LineNumberMetrics.gutterWidth(forLineCount: 9, font: font)
        XCTAssertEqual(singleDigitWidth, LineNumberMetrics.gutterWidth(forLineCount: 1, font: font))
        XCTAssertGreaterThan(LineNumberMetrics.gutterWidth(forLineCount: 10, font: font), singleDigitWidth)
        XCTAssertGreaterThan(LineNumberMetrics.gutterWidth(forLineCount: 1_000, font: font), singleDigitWidth)
    }

    func testGutterGeometryKeepsMarkerAndNumberZonesSeparateAcrossDigitTransitions() {
        let font = EditorConfiguration.Gutter.font
        let counts = [9, 10, 99, 100]
        let geometries = counts.map { LineNumberMetrics.gutterGeometry(forLineCount: $0, font: font) }

        XCTAssertTrue(geometries.allSatisfy { $0.markerZone.width == EditorConfiguration.Gutter.markerZoneWidth })
        XCTAssertTrue(geometries.allSatisfy { $0.markerOriginX == geometries[0].markerOriginX })
        XCTAssertTrue(geometries.allSatisfy { $0.lineNumberZone.minX == $0.markerZone.maxX })
        XCTAssertTrue(geometries.allSatisfy { $0.separatorZone.width == EditorConfiguration.Gutter.separatorZoneWidth })

        for (count, geometry) in zip(counts, geometries) {
            let label = String(count) as NSString
            let labelWidth = ceil(label.size(withAttributes: [.font: font]).width)
            XCTAssertEqual(
                geometry.lineNumberOriginX(for: labelWidth),
                geometry.markerZone.maxX + EditorConfiguration.Gutter.markerToNumberSpacing,
                accuracy: 0.001
            )
        }
    }

    func testEditorPresentationConfiguration() {
        XCTAssertEqual(EditorConfiguration.preferredColumn, 80)
        XCTAssertEqual(EditorConfiguration.Text.fontSize, 14)
        XCTAssertEqual(EditorConfiguration.Text.font.pointSize, 14)
        XCTAssertGreaterThan(EditorConfiguration.StatusBar.height, 0)
        XCTAssertGreaterThan(EditorConfiguration.Gutter.horizontalChromeWidth, 0)

        let font = EditorConfiguration.Text.font
        XCTAssertEqual(
            EditorConfiguration.preferredColumnX(textContainerOriginX: 12, font: font),
            12 + font.maximumAdvancement.width * 80,
            accuracy: 0.001
        )
    }

    func testScopeLightPaletteResolvesEveryHighlightCategory() {
        let categories: [HighlightCategory] = [.keyword, .comment, .string, .number, .constant, .function, .symbol]
        for category in categories {
            XCTAssertNotNil(SyntaxTheme.color(for: category).usingColorSpace(.sRGB))
        }
    }

    func testLargeRubyFixtureAnalysisRemainsStructural() {
        let source = (1...750).map { index in
            """
            def fixture_\(index)
              puts \"fixture \(index)\"
            end
            # fixture \(index)
            """
        }.joined(separator: "\n")

        XCTAssertEqual(source.split(separator: "\n").count, 3_000)
        let analysis = SyntaxHighlighter.analyze(language: .ruby, source: source)
        XCTAssertEqual(analysis.foldRanges.count, 750)
        XCTAssertFalse(analysis.highlightSpans.isEmpty)
        XCTAssertEqual(source.split(separator: "\n").count, 3_000)
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
