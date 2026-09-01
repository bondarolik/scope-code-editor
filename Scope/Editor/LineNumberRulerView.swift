import AppKit

enum LineNumberMetrics {
    struct GutterGeometry: Equatable {
        let markerZone: NSRect
        let lineNumberZone: NSRect
        let separatorZone: NSRect

        var width: CGFloat { separatorZone.maxX }

        func lineNumberOriginX(for labelWidth: CGFloat) -> CGFloat {
            lineNumberZone.maxX - EditorConfiguration.Gutter.numberTrailingPadding - labelWidth
        }

        var markerOriginX: CGFloat {
            markerZone.midX - (EditorConfiguration.Gutter.markerWidth / 2)
        }
    }

    static func lineCount(in text: String) -> Int {
        text.isEmpty ? 1 : text.reduce(into: 1) { $0 += $1 == "\n" ? 1 : 0 }
    }

    static func gutterWidth(forLineCount count: Int, font: NSFont) -> CGFloat {
        gutterGeometry(forLineCount: count, font: font).width
    }

    static func gutterGeometry(forLineCount count: Int, font: NSFont) -> GutterGeometry {
        let digits = max(1, String(count).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let lineNumberWidth = ceil(sample.size(withAttributes: [.font: font]).width)
        let markerZone = NSRect(x: 0, y: 0, width: EditorConfiguration.Gutter.markerZoneWidth, height: 0)
        let lineNumberZone = NSRect(
            x: markerZone.maxX,
            y: 0,
            width: EditorConfiguration.Gutter.markerToNumberSpacing + lineNumberWidth + EditorConfiguration.Gutter.numberTrailingPadding,
            height: 0
        )
        let separatorZone = NSRect(
            x: lineNumberZone.maxX,
            y: 0,
            width: EditorConfiguration.Gutter.separatorZoneWidth,
            height: 0
        )
        return GutterGeometry(
            markerZone: markerZone,
            lineNumberZone: lineNumberZone,
            separatorZone: separatorZone
        )
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
        ruleThickness = LineNumberMetrics.gutterWidth(forLineCount: 1, font: EditorConfiguration.Gutter.font)
        needsDisplay = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let font = EditorConfiguration.Gutter.font
        let text = textView.string as NSString
        let geometry = LineNumberMetrics.gutterGeometry(
            forLineCount: LineNumberMetrics.lineCount(in: textView.string),
            font: font
        )
        ruleThickness = geometry.width
        let separator = NSBezierPath()
        let separatorX = geometry.separatorZone.minX + EditorConfiguration.Gutter.separatorPixelOffset
        separator.move(to: NSPoint(x: separatorX, y: rect.minY))
        separator.line(to: NSPoint(x: separatorX, y: rect.maxY))
        separator.lineWidth = EditorConfiguration.Ruler.lineWidth
        ScopeLightPalette.gutterSeparator.setStroke()
        separator.stroke()

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
                let labelWidth = ceil(labelSize.width)
                let lineY = lineRect.minY + textView.textContainerOrigin.y
                let labelY = lineY + ((lineRect.height - labelSize.height) / 2)
                label.draw(
                    at: NSPoint(x: geometry.lineNumberOriginX(for: labelWidth), y: labelY),
                    withAttributes: [.font: font, .foregroundColor: ScopeLightPalette.gutterText]
                )

                if let range = foldRanges.first(where: { $0.startLine == lineNumber }) {
                    let frame = NSRect(
                        x: geometry.markerOriginX,
                        y: lineY + ((lineRect.height - EditorConfiguration.Gutter.markerWidth) / 2),
                        width: EditorConfiguration.Gutter.markerWidth,
                        height: EditorConfiguration.Gutter.markerWidth
                    )
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
        if let disclosure = disclosureFrames.first(where: {
            $0.frame.insetBy(
                dx: -EditorConfiguration.Gutter.disclosureHitExpansion,
                dy: -EditorConfiguration.Gutter.disclosureHitExpansion
            ).contains(point)
        }) {
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
            let leadingX = frame.minX + EditorConfiguration.Gutter.collapsedTriangleLeadingInset
            let verticalInset = EditorConfiguration.Gutter.collapsedTriangleVerticalInset
            path.move(to: NSPoint(x: leadingX, y: frame.minY + verticalInset))
            path.line(to: NSPoint(x: leadingX, y: frame.maxY - verticalInset))
            path.line(to: NSPoint(x: frame.maxX - EditorConfiguration.Gutter.expandedTriangleHorizontalInset, y: frame.midY))
        } else {
            let horizontalInset = EditorConfiguration.Gutter.expandedTriangleHorizontalInset
            path.move(to: NSPoint(x: frame.minX + horizontalInset, y: frame.maxY - EditorConfiguration.Gutter.expandedTriangleTopInset))
            path.line(to: NSPoint(x: frame.maxX - horizontalInset, y: frame.maxY - EditorConfiguration.Gutter.expandedTriangleTopInset))
            path.line(to: NSPoint(x: frame.midX, y: frame.minY + EditorConfiguration.Gutter.collapsedTriangleVerticalInset))
        }
        path.close()
        ScopeLightPalette.foldMarker.setFill()
        path.fill()
    }
}
