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
                folds: Self.structuralFolds(in: tree, source: source as NSString)
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

    private static func structuralFolds(in tree: MutableTree, source: NSString) -> [StructuralFold] {
        guard let root = tree.rootNode else { return [] }
        var folds = [StructuralFold]()
        collectFolds(from: root, source: source, into: &folds)
        var seen = Set<FoldRange>()
        return folds.filter { seen.insert($0.range).inserted }.sorted { lhs, rhs in
            lhs.range.startLine == rhs.range.startLine
                ? lhs.range.endLine > rhs.range.endLine
                : lhs.range.startLine < rhs.range.startLine
        }
    }

    private static func collectFolds(from node: Node, source: NSString, into folds: inout [StructuralFold]) {
        if let kind = node.nodeType, foldableNodeTypes.contains(kind), !node.hasError,
           let opener = node.child(at: 0), let closer = node.child(at: node.childCount - 1),
           opener.range.length > 0, closer.range.length > 0 {
            let range = FoldRange(
                startLine: Int(node.pointRange.lowerBound.row) + 1,
                endLine: Int(node.pointRange.upperBound.row) + 1,
                closingToken: explicitClosingToken(for: node)
            )
            if range.foldedLineCount > 0 {
                // Endless methods have an expression at their endpoint instead of a delimiter.
                let closingStart = closer.nodeType == "end" || closer.nodeType == "}"
                    ? closer.range.location
                    : closer.range.upperBound - 1
                var contentsEnd = 0
                source.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: closingStart, length: 0))
                folds.append(StructuralFold(range: range, anchors: .init(
                    kind: kind,
                    openingToken: opener.range,
                    closingLineTail: NSRange(location: closingStart, length: contentsEnd - closingStart)
                )))
            }
        }

        node.enumerateChildren { child in
            collectFolds(from: child, source: source, into: &folds)
        }
    }

    private static let foldableNodeTypes: Set<String> = [
        "class", "module", "method", "singleton_method", "singleton_class", "block", "do_block"
    ]

    private static func explicitClosingToken(for node: Node) -> String? {
        switch node.nodeType {
        case "class", "module", "method", "singleton_method", "singleton_class", "do_block":
            return "end"
        default:
            return nil
        }
    }

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
