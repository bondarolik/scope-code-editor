import Foundation
import SwiftTreeSitter
import TreeSitterRuby

struct RubySyntaxHighlighter {
    private static let queryBundleName = "TreeSitterRuby_TreeSitterRuby.bundle"

    func canParse(_ source: String) -> Bool {
        do {
            let parser = Parser()
            try parser.setLanguage(Language(language: tree_sitter_ruby()))
            return parser.parse(source) != nil
        } catch {
            return false
        }
    }

    func analyze(_ source: String) -> SyntaxAnalysis {
        do {
            let parser = Parser()
            try parser.setLanguage(Language(language: tree_sitter_ruby()))
            guard let tree = parser.parse(source) else {
                return .empty
            }

            return SyntaxAnalysis(
                highlightSpans: Self.highlightSpans(in: tree, source: source),
                foldRanges: Self.foldRanges(in: tree)
            )
        } catch {
            return .empty
        }
    }

    func highlightSpans(in source: String) -> [HighlightSpan] {
        analyze(source).highlightSpans
    }

    func foldRanges(in source: String) -> [FoldRange] {
        analyze(source).foldRanges
    }

    private static func highlightSpans(in tree: MutableTree, source: String) -> [HighlightSpan] {
        guard let queriesURL, let configuration = try? LanguageConfiguration(
            tree_sitter_ruby(),
            name: "Ruby",
            queriesURL: queriesURL
        ), let query = configuration.queries[.highlights] else {
            return []
        }

        return query.execute(in: tree)
            .resolve(with: .init(string: source))
            .highlights()
            .compactMap { capture in
                guard let category = category(for: capture.name) else { return nil }
                return HighlightSpan(range: capture.range, category: category)
            }
    }

    private static func foldRanges(in tree: MutableTree) -> [FoldRange] {
        guard let root = tree.rootNode else { return [] }
        var ranges = Set<FoldRange>()
        collectFoldRanges(from: root, into: &ranges)
        return ranges.sorted { lhs, rhs in
            lhs.startLine == rhs.startLine ? lhs.endLine > rhs.endLine : lhs.startLine < rhs.startLine
        }
    }

    private static func collectFoldRanges(from node: Node, into ranges: inout Set<FoldRange>) {
        if foldableNodeTypes.contains(node.nodeType ?? ""), !node.hasError {
            let range = FoldRange(
                startLine: Int(node.pointRange.lowerBound.row) + 1,
                endLine: Int(node.pointRange.upperBound.row) + 1
            )
            if range.foldedLineCount > 0 {
                ranges.insert(range)
            }
        }

        node.enumerateChildren { child in
            collectFoldRanges(from: child, into: &ranges)
        }
    }

    private static let foldableNodeTypes: Set<String> = [
        "class", "module", "method", "singleton_method", "singleton_class", "block", "do_block"
    ]

    private static var queriesURL: URL? {
        let resourceLocations = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
            Bundle.main.bundleURL
        ].compactMap { $0 }

        return resourceLocations
            .map {
                $0
                    .appendingPathComponent(queryBundleName, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/queries", isDirectory: true)
            }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    static func category(for capture: String) -> HighlightCategory? {
        if capture.hasPrefix("keyword") { return .keyword }
        if capture.hasPrefix("comment") { return .comment }
        if capture.contains("symbol") { return .symbol }
        if capture.hasPrefix("string") { return .string }
        if capture.hasPrefix("number") { return .number }
        if capture.hasPrefix("constant") || capture.hasPrefix("constructor") { return .constant }
        if capture.hasPrefix("function") { return .function }
        return nil
    }
}
