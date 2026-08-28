import AppKit

enum LineNumberMetrics {
    static func lineCount(in text: String) -> Int {
        text.isEmpty ? 1 : text.reduce(into: 1) { $0 += $1 == "\n" ? 1 : 0 }
    }

    static func gutterWidth(forLineCount count: Int, font: NSFont) -> CGFloat {
        let digits = max(1, String(count).count)
        let sample = String(repeating: "8", count: digits) as NSString
        return ceil(sample.size(withAttributes: [.font: font]).width) + 24
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var foldRanges = [FoldRange]() {
        didSet { needsDisplay = true }
    }
    var collapsedFoldRanges = Set<FoldRange>() {
        didSet { needsDisplay = true }
    }
    var onToggleFold: ((FoldRange) -> Void)?
    private var disclosureFrames = [(frame: NSRect, range: FoldRange)]()

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
        disclosureFrames.removeAll()

        while lineStart < text.length && lineStart < NSMaxRange(characterRange) {
            if !isHidden(line: lineNumber) {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let label = "\(lineNumber)" as NSString
                let labelSize = label.size(withAttributes: [.font: font])
                let y = lineRect.minY + textView.textContainerOrigin.y
                label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 10, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])

                if let range = foldRanges.first(where: { $0.startLine == lineNumber }) {
                    let frame = NSRect(x: 4, y: y + 2, width: 10, height: max(10, lineRect.height - 4))
                    drawDisclosure(in: frame, collapsed: collapsedFoldRanges.contains(range))
                    disclosureFrames.append((frame: frame, range: range))
                }
            }

            guard lineEnd > lineStart else { break }
            lineStart = lineEnd
            lineNumber += 1
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let disclosure = disclosureFrames.first(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }) {
            onToggleFold?(disclosure.range)
            return
        }
        super.mouseDown(with: event)
    }

    private func isHidden(line: Int) -> Bool {
        collapsedFoldRanges.contains { line > $0.startLine && line <= $0.endLine }
    }

    private func drawDisclosure(in frame: NSRect, collapsed: Bool) {
        let path = NSBezierPath()
        if collapsed {
            path.move(to: NSPoint(x: frame.minX + 3, y: frame.minY + 2))
            path.line(to: NSPoint(x: frame.minX + 3, y: frame.maxY - 2))
            path.line(to: NSPoint(x: frame.maxX - 2, y: frame.midY))
        } else {
            path.move(to: NSPoint(x: frame.minX + 2, y: frame.maxY - 3))
            path.line(to: NSPoint(x: frame.maxX - 2, y: frame.maxY - 3))
            path.line(to: NSPoint(x: frame.midX, y: frame.minY + 2))
        }
        path.close()
        NSColor.tertiaryLabelColor.setFill()
        path.fill()
    }
}
