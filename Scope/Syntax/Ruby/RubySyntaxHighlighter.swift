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

    func highlightSpans(in source: String) -> [HighlightSpan] {
        do {
            guard let queriesURL = Self.queriesURL else { return [] }
            let configuration = try LanguageConfiguration(
                tree_sitter_ruby(),
                name: "Ruby",
                queriesURL: queriesURL
            )
            let parser = Parser()
            try parser.setLanguage(configuration.language)
            guard let tree = parser.parse(source), let query = configuration.queries[.highlights] else {
                return []
            }
            return query.execute(in: tree)
                .resolve(with: .init(string: source))
                .highlights()
                .compactMap { capture in
                    guard let category = Self.category(for: capture.name) else { return nil }
                    return HighlightSpan(range: capture.range, category: category)
                }
        } catch {
            return []
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
