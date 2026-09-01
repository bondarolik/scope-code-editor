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
        case .keyword: ScopeLightPalette.keyword
        case .comment: ScopeLightPalette.comment
        case .string: ScopeLightPalette.string
        case .number: ScopeLightPalette.number
        case .constant: ScopeLightPalette.constant
        case .symbol: ScopeLightPalette.symbol
        case .function: ScopeLightPalette.function
        }
    }
}

enum ScopeLightPalette {
    // Syntax intentionally uses a compact set of muted semantic colors. Structural
    // editor chrome remains neutral and is defined separately below.
    static let keyword = NSColor(srgbRed: 0.34, green: 0.30, blue: 0.57, alpha: 1)
    static let comment = NSColor.secondaryLabelColor
    static let string = NSColor(srgbRed: 0.54, green: 0.31, blue: 0.24, alpha: 1)
    static let number = NSColor(srgbRed: 0.30, green: 0.39, blue: 0.59, alpha: 1)
    static let constant = NSColor(srgbRed: 0.20, green: 0.44, blue: 0.47, alpha: 1)
    static let symbol = NSColor(srgbRed: 0.43, green: 0.34, blue: 0.52, alpha: 1)
    static let function = NSColor.labelColor

    static let gutterText = NSColor.secondaryLabelColor
    static let gutterCurrentLineText = NSColor.labelColor
    static let gutterSeparator = NSColor.separatorColor.withAlphaComponent(0.55)
    static let foldMarker = NSColor.secondaryLabelColor
    static let foldEllipsis = NSColor.secondaryLabelColor
    static let gutterCurrentLine = NSColor.controlAccentColor.withAlphaComponent(EditorConfiguration.Gutter.currentLineBackgroundAlpha)
    static let currentLine = NSColor.controlAccentColor.withAlphaComponent(EditorConfiguration.CurrentLine.accentAlpha)
    static let preferredColumnRuler = NSColor.separatorColor.withAlphaComponent(EditorConfiguration.Ruler.separatorAlpha)
    static let statusText = NSColor.secondaryLabelColor
    static let statusBackground = NSColor.controlBackgroundColor
    static let statusSeparator = NSColor.separatorColor.withAlphaComponent(0.55)
}

enum SyntaxHighlighter {
    static func spans(for language: LanguageID?, source: String) -> [HighlightSpan] {
        analyze(language: language, source: source).highlightSpans
    }

    static func analyze(language: LanguageID?, source: String) -> SyntaxAnalysis {
        LanguageDefinition.definition(for: language)?.analyzeSyntax(in: source) ?? .empty
    }
}
