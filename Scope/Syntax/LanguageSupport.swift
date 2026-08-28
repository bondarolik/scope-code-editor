import AppKit
import Foundation

enum LanguageID: Equatable {
    case ruby

    var displayName: String {
        switch self {
        case .ruby: "Ruby"
        }
    }
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
    private let analyze: (String) -> SyntaxAnalysis

    func highlightSpans(in source: String) -> [HighlightSpan] {
        analyze(source).highlightSpans
    }

    func analyzeSyntax(in source: String) -> SyntaxAnalysis {
        analyze(source)
    }

    static let ruby = LanguageDefinition(id: .ruby) { source in
        RubySyntaxHighlighter().analyze(source)
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
        analyze(language: language, source: source).highlightSpans
    }

    static func analyze(language: LanguageID?, source: String) -> SyntaxAnalysis {
        LanguageDefinition.definition(for: language)?.analyzeSyntax(in: source) ?? .empty
    }
}
