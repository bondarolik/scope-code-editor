import AppKit
import Foundation

enum LanguageID: Equatable {
    case ruby
}

enum LanguageDetector {
    static func language(for url: URL?) -> LanguageID? {
        url?.pathExtension.lowercased() == "rb" ? .ruby : nil
    }
}

enum HighlightCategory: Equatable {
    case keyword
    case comment
    case string
    case number
    case constant
    case function
    case symbol
}

struct HighlightSpan: Equatable { let range: NSRange; let category: HighlightCategory }

struct LanguageDefinition {
    let id: LanguageID
    private let highlight: (String) -> [HighlightSpan]

    func highlightSpans(in source: String) -> [HighlightSpan] {
        highlight(source)
    }

    static let ruby = LanguageDefinition(id: .ruby) { source in
        RubySyntaxHighlighter().highlightSpans(in: source)
    }

    static func definition(for language: LanguageID?) -> LanguageDefinition? {
        guard language == .ruby else { return nil }
        return .ruby
    }
}

enum SyntaxTheme {
    static func color(for category: HighlightCategory) -> NSColor {
        switch category {
        case .keyword: .systemPurple
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .number: .systemBlue
        case .constant: .systemTeal
        case .symbol: .systemOrange
        case .function: .labelColor
        }
    }
}

enum SyntaxHighlighter {
    static func spans(for language: LanguageID?, source: String) -> [HighlightSpan] {
        LanguageDefinition.definition(for: language)?.highlightSpans(in: source) ?? []
    }
}
