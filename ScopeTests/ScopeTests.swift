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
            [FoldRange(startLine: 1, endLine: 3, closingToken: "end")]
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
                FoldRange(startLine: 1, endLine: 7, closingToken: "end"),
                FoldRange(startLine: 2, endLine: 6, closingToken: "end"),
                FoldRange(startLine: 3, endLine: 5, closingToken: "end")
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

    func testEditorGutterMetricsTracksLogicalLinesAndWidth() {
        XCTAssertEqual(EditorGutterMetrics.LogicalLineIndex(source: "").lineCount, 1)
        XCTAssertEqual(EditorGutterMetrics.LogicalLineIndex(source: "one\ntwo\nthree").lineCount, 3)
        let font = EditorConfiguration.Gutter.font
        let minimumWidth = EditorGutterMetrics.gutterGeometry(forLineCount: 9, font: font).width
        XCTAssertEqual(minimumWidth, EditorGutterMetrics.gutterGeometry(forLineCount: 1, font: font).width)
        XCTAssertEqual(minimumWidth, EditorGutterMetrics.gutterGeometry(forLineCount: 1_000, font: font).width)
        XCTAssertGreaterThan(EditorGutterMetrics.gutterGeometry(forLineCount: 10_000, font: font).width, minimumWidth)
    }

    func testLogicalLineIndexMapsVisualFragmentsToUniqueSourceLines() {
        let source = "first\nthis is a deliberately long source line for wrapping\nnext\nlast"
        let index = EditorGutterMetrics.LogicalLineIndex(source: source)
        let text = source as NSString
        let longLineStart = text.range(of: "this is").location
        let nextLineStart = text.range(of: "next").location

        XCTAssertEqual(index.line(containing: 0)?.number, 1)
        XCTAssertEqual(index.line(containing: longLineStart)?.number, 2)
        XCTAssertEqual(index.line(containing: nextLineStart)?.number, 3)

        XCTAssertEqual(index.visibleLines(intersecting: NSRange(location: longLineStart, length: nextLineStart - longLineStart), overscan: 0).map(\.number), [2])
        XCTAssertEqual(source, "first\nthis is a deliberately long source line for wrapping\nnext\nlast")
    }

    func testLogicalLineIndexRetainsSourceNumbersAfterFoldedContent() {
        let source = """
        class Example
          def foo
            very_long_call(with: :a, and: :b, and: :c, and: :d)
          end

          def bar
            work
          end
        end
        """
        let index = EditorGutterMetrics.LogicalLineIndex(source: source)
        let text = source as NSString
        let wrappedFoldStart = text.range(of: "very_long_call").location
        let laterMethodStart = text.range(of: "def bar").location

        XCTAssertEqual(index.line(containing: wrappedFoldStart)?.number, 3)
        XCTAssertEqual(index.line(containing: laterMethodStart)?.number, 6)
        XCTAssertEqual(index.visibleLines(intersecting: NSRange(location: wrappedFoldStart, length: laterMethodStart - wrappedFoldStart + 7), overscan: 0).map(\.number), [3, 4, 5, 6])
        XCTAssertEqual(source, """
        class Example
          def foo
            very_long_call(with: :a, and: :b, and: :c, and: :d)
          end

          def bar
            work
          end
        end
        """)
    }

    func testGutterGeometryKeepsMarkerAndNumberZonesSeparateAcrossDigitTransitions() {
        let font = EditorConfiguration.Gutter.font
        let counts = [9, 10, 99, 100]
        let geometries = counts.map { EditorGutterMetrics.gutterGeometry(forLineCount: $0, font: font) }

        XCTAssertTrue(geometries.allSatisfy { $0.foldMarkerZone.width == EditorConfiguration.Gutter.foldMarkerZoneWidth })
        XCTAssertTrue(geometries.allSatisfy { $0.markerOriginX == geometries[0].markerOriginX })
        XCTAssertTrue(geometries.allSatisfy { $0.foldMarkerZone.minX == $0.lineNumberZone.maxX + EditorConfiguration.Gutter.foldMarkerGap })
        XCTAssertTrue(geometries.allSatisfy { $0.separatorZone.width == EditorConfiguration.Gutter.gutterSeparatorWidth })

        for (count, geometry) in zip(counts, geometries) {
            let label = String(count) as NSString
            let labelWidth = ceil(label.size(withAttributes: [.font: font]).width)
            XCTAssertEqual(
                geometry.lineNumberOriginX(for: labelWidth),
                geometry.lineNumberZone.midX - (labelWidth / 2),
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

    @MainActor func testSessionDeduplicatesOpenFilesAndClosesToAdjacentDocument() throws {
        let firstURL = try makeTemporaryFile(contents: "first")
        let secondURL = try makeTemporaryFile(contents: "second")
        let suiteName = "ScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let session = EditorSession(documentSessionStore: DocumentSessionStore(defaults: defaults), restoreSession: false)

        session.open(firstURL, recordRecent: false)
        session.open(secondURL, recordRecent: false)
        session.open(firstURL, recordRecent: false)

        XCTAssertEqual(session.documents.count, 2)
        XCTAssertEqual(session.activeDocument?.fileURL, firstURL.standardizedFileURL)
        session.close(session.activeDocument!)
        XCTAssertEqual(session.documents.count, 1)
        XCTAssertEqual(session.activeDocument?.fileURL, secondURL.standardizedFileURL)
    }

    func testDocumentSessionStoreRoundTripsActiveDocument() {
        let defaults = UserDefaults(suiteName: "ScopeTests.\(UUID().uuidString)")!
        let store = DocumentSessionStore(defaults: defaults)
        let document = RestorableDocument(id: UUID(), bookmarkData: Data([1, 2]), displayPath: "/tmp/example.rb")

        store.save(.init(documents: [document], activeDocumentID: document.id))

        XCTAssertEqual(store.load(), .init(documents: [document], activeDocumentID: document.id))
        store.clear()
        XCTAssertEqual(store.load().documents, [])
    }

    func testDocumentTabTitleDisambiguatesOnlyDuplicateFilenames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstDirectory = root.appendingPathComponent("one")
        let secondDirectory = root.appendingPathComponent("two")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstURL = firstDirectory.appendingPathComponent("example.rb")
        let secondURL = secondDirectory.appendingPathComponent("example.rb")
        try "one".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two".write(to: secondURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let first = EditorDocument(); try first.load(from: firstURL)
        let second = EditorDocument(); try second.load(from: secondURL)

        XCTAssertEqual(DocumentTabTitle.title(for: first, among: [first, second]), "example.rb — one")
        XCTAssertEqual(DocumentTabTitle.title(for: second, among: [first, second]), "example.rb — two")
        XCTAssertEqual(DocumentTabTitle.title(for: first, among: [first]), "example.rb")
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
