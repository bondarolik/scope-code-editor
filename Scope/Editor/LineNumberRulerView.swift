import AppKit

enum LineNumberMetrics {
    static func lineCount(in text: String) -> Int {
        text.isEmpty ? 1 : text.reduce(into: 1) { $0 += $1 == "\n" ? 1 : 0 }
    }

    static func gutterWidth(forLineCount count: Int, font: NSFont) -> CGFloat {
        let digits = max(1, String(count).count)
        let sample = String(repeating: "8", count: digits) as NSString
        return ceil(sample.size(withAttributes: [.font: font]).width) + 20
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = LineNumberMetrics.gutterWidth(forLineCount: 1, font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
        needsDisplay = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let text = textView.string as NSString
        ruleThickness = LineNumberMetrics.gutterWidth(forLineCount: LineNumberMetrics.lineCount(in: textView.string), font: font)

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard text.length > 0 else { return }

        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: characterRange.location, length: 0))
        var lineNumber = text.substring(to: lineStart).reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }

        while lineStart < text.length && lineStart < NSMaxRange(characterRange) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: [.font: font])
            let y = lineRect.minY + textView.textContainerOrigin.y
            label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 10, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])

            guard lineEnd > lineStart else { break }
            lineStart = lineEnd
            lineNumber += 1
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
        }
    }
}
