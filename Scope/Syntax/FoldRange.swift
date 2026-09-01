import Foundation

struct FoldRange: Equatable, Hashable {
    let startLine: Int
    let endLine: Int
    let closingToken: String?

    init(startLine: Int, endLine: Int, closingToken: String? = nil) {
        self.startLine = startLine
        self.endLine = endLine
        self.closingToken = closingToken
    }

    var foldedLineCount: Int {
        endLine - startLine
    }

    func hiddenCharacterRange(in source: String) -> NSRange? {
        let text = source as NSString
        guard startLine >= 1, endLine > startLine, text.length > 0 else { return nil }

        var currentLine = 1
        var location = 0
        var start = 0
        var end = 0
        var contentsEnd = 0

        while location < text.length {
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            if currentLine == startLine {
                let hiddenStart = end
                while location < text.length, currentLine < endLine {
                    location = end
                    currentLine += 1
                    guard location < text.length else { return nil }
                    text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
                }
                guard currentLine == endLine else { return nil }
                return NSRange(location: hiddenStart, length: end - hiddenStart)
            }
            location = end
            currentLine += 1
        }
        return nil
    }

    func startCharacterLocation(in source: String) -> Int? {
        let text = source as NSString
        var currentLine = 1
        var location = 0
        var start = 0
        var end = 0
        var contentsEnd = 0

        while location < text.length {
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            if currentLine == startLine { return start }
            location = end
            currentLine += 1
        }
        return nil
    }
}

struct SyntaxAnalysis {
    let highlightSpans: [HighlightSpan]
    let foldRanges: [FoldRange]

    static let empty = SyntaxAnalysis(highlightSpans: [], foldRanges: [])
}
