import AppKit

enum EditorGutterMetrics {
    struct LogicalSourceLine: Equatable {
        let number: Int
        let characterRange: NSRange

        var startLocation: Int { characterRange.location }
        var endLocation: Int { NSMaxRange(characterRange) }
    }

    struct LogicalLineIndex {
        private let lines: [LogicalSourceLine]

        var lineCount: Int { lines.count }

        init(source: String) {
            let text = source as NSString
            guard text.length > 0 else {
                lines = [LogicalSourceLine(number: 1, characterRange: NSRange(location: 0, length: 0))]
                return
            }

            var indexedLines = [LogicalSourceLine]()
            var location = 0
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0

            while location < text.length {
                text.getLineStart(
                    &lineStart,
                    end: &lineEnd,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: location, length: 0)
                )
                indexedLines.append(
                    LogicalSourceLine(
                        number: indexedLines.count + 1,
                        characterRange: NSRange(location: lineStart, length: lineEnd - lineStart)
                    )
                )
                location = lineEnd
            }

            if text.character(at: text.length - 1) == 10 {
                indexedLines.append(
                    LogicalSourceLine(
                        number: indexedLines.count + 1,
                        characterRange: NSRange(location: text.length, length: 0)
                    )
                )
            }
            lines = indexedLines
        }

        func visibleLines(intersecting characterRange: NSRange, overscan: Int = 2) -> ArraySlice<LogicalSourceLine> {
            guard !lines.isEmpty else { return [] }

            let viewportStart = characterRange.location
            let viewportEnd = NSMaxRange(characterRange)
            let first = firstIndex(whoseEndIsAfter: viewportStart)
            let last = firstIndex(startingAtOrAfter: viewportEnd)
            let start = max(0, first - overscan)
            let end = min(lines.count, max(first + 1, last) + overscan)
            return lines[start..<end]
        }

        func line(containing characterLocation: Int) -> LogicalSourceLine? {
            guard !lines.isEmpty else { return nil }
            if characterLocation == lines[lines.count - 1].endLocation {
                return lines[lines.count - 1]
            }
            let index = firstIndex(startingAtOrAfter: characterLocation + 1)
            let candidate = lines[max(0, index - 1)]
            if candidate.characterRange.length == 0 {
                return candidate.startLocation == characterLocation ? candidate : nil
            }
            return NSLocationInRange(characterLocation, candidate.characterRange) ? candidate : nil
        }

        private func firstIndex(whoseEndIsAfter location: Int) -> Int {
            var lowerBound = 0
            var upperBound = lines.count
            while lowerBound < upperBound {
                let midpoint = (lowerBound + upperBound) / 2
                if lines[midpoint].endLocation > location {
                    upperBound = midpoint
                } else {
                    lowerBound = midpoint + 1
                }
            }
            return min(lowerBound, lines.count - 1)
        }

        private func firstIndex(startingAtOrAfter location: Int) -> Int {
            var lowerBound = 0
            var upperBound = lines.count
            while lowerBound < upperBound {
                let midpoint = (lowerBound + upperBound) / 2
                if lines[midpoint].startLocation >= location {
                    upperBound = midpoint
                } else {
                    lowerBound = midpoint + 1
                }
            }
            return lowerBound
        }
    }

    struct GutterGeometry: Equatable {
        let lineNumberZone: NSRect
        let foldMarkerZone: NSRect
        let separatorZone: NSRect

        var width: CGFloat { separatorZone.maxX }

        func lineNumberOriginX(for labelWidth: CGFloat) -> CGFloat {
            lineNumberZone.midX - (labelWidth / 2)
        }

        var markerOriginX: CGFloat {
            foldMarkerZone.midX - (EditorConfiguration.Gutter.foldMarkerWidth / 2)
        }
    }

    static func labelOriginY(forLineFragment lineFragment: NSRect, originY: CGFloat, font: NSFont) -> CGFloat {
        lineFragment.minY + originY + ((lineFragment.height - font.boundingRectForFont.height) / 2)
    }

    static func gutterGeometry(forLineCount count: Int, font: NSFont) -> GutterGeometry {
        let digits = max(EditorConfiguration.Gutter.lineNumberMinimumDigits, String(count).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let lineNumberWidth = ceil(sample.size(withAttributes: [.font: font]).width)
        let lineNumberZone = NSRect(
            x: 0,
            y: 0,
            width: EditorConfiguration.Gutter.lineNumberLeadingPadding + lineNumberWidth + EditorConfiguration.Gutter.lineNumberTrailingPadding,
            height: 0
        )
        let foldMarkerZone = NSRect(
            x: lineNumberZone.maxX + EditorConfiguration.Gutter.foldMarkerGap,
            y: 0,
            width: EditorConfiguration.Gutter.foldMarkerZoneWidth,
            height: 0
        )
        let separatorZone = NSRect(
            x: foldMarkerZone.maxX + EditorConfiguration.Gutter.gutterTrailingPadding,
            y: 0,
            width: EditorConfiguration.Gutter.gutterSeparatorWidth,
            height: 0
        )
        return GutterGeometry(lineNumberZone: lineNumberZone, foldMarkerZone: foldMarkerZone, separatorZone: separatorZone)
    }
}

final class EditorGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    var foldRanges = [FoldRange]() {
        didSet {
            foldRangesByStartLine = Dictionary(uniqueKeysWithValues: foldRanges.map { ($0.startLine, $0) })
            needsDisplay = true
        }
    }
    var collapsedFoldRanges = Set<FoldRange>() {
        didSet { needsDisplay = true }
    }
    var onToggleFold: ((FoldRange) -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?

    private var logicalLineIndex: EditorGutterMetrics.LogicalLineIndex
    private var foldRangesByStartLine = [Int: FoldRange]()
    private var disclosureFrames = [(frame: NSRect, range: FoldRange)]()
    private var boundsObserver: NSObjectProtocol?

    var preferredWidth: CGFloat {
        EditorGutterMetrics.gutterGeometry(
            forLineCount: logicalLineIndex.lineCount,
            font: EditorConfiguration.Gutter.font
        ).width
    }

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        logicalLineIndex = EditorGutterMetrics.LogicalLineIndex(source: textView.string)
        super.init(frame: .zero)
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        notifyWidthChange()
    }

    required init?(coder: NSCoder) {
        logicalLineIndex = EditorGutterMetrics.LogicalLineIndex(source: "")
        super.init(coder: coder)
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func updateSourceText(_ source: String) {
        logicalLineIndex = EditorGutterMetrics.LogicalLineIndex(source: source)
        notifyWidthChange()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let textView, let codeTextView = textView as? CodeTextView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer, let scrollView else { return }

        let font = EditorConfiguration.Gutter.font
        let geometry = EditorGutterMetrics.gutterGeometry(forLineCount: logicalLineIndex.lineCount, font: font)
        disclosureFrames.removeAll()

        let viewport = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: viewport, in: textContainer)
        let visiblePresentationRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let visibleSourceRange = codeTextView.projection.sourceRange(coveringPresentationRange: visiblePresentationRange)
        let candidates = logicalLineIndex.visibleLines(intersecting: visibleSourceRange)
        let originY = textView.textContainerOrigin.y - viewport.minY
        let currentSourceLocation = codeTextView.sourceLocation(forPresentationLocation: textView.selectedRange().location)
        let currentLineNumber = logicalLineIndex.line(containing: currentSourceLocation)?.number

        for line in candidates where !isHidden(line: line.number) {
            guard let lineFragment = firstLineFragment(for: line, in: codeTextView, layoutManager: layoutManager) else { continue }
            let lineY = lineFragment.minY + originY
            let isCurrentLine = line.number == currentLineNumber
            if isCurrentLine {
                ScopeLightPalette.gutterCurrentLine.setFill()
                NSRect(x: 0, y: lineY, width: bounds.width, height: lineFragment.height).fill()
            }
            let label = "\(line.number)" as NSString
            let labelWidth = ceil(label.size(withAttributes: [.font: font]).width)
            let labelY = EditorGutterMetrics.labelOriginY(forLineFragment: lineFragment, originY: originY, font: font)
            label.draw(
                at: NSPoint(x: geometry.lineNumberOriginX(for: labelWidth), y: labelY),
                withAttributes: [
                    .font: font,
                    .foregroundColor: isCurrentLine ? ScopeLightPalette.gutterCurrentLineText : ScopeLightPalette.gutterText
                ]
            )

            if let range = foldRangesByStartLine[line.number] {
                let frame = NSRect(
                    x: geometry.markerOriginX,
                    y: lineY + ((lineFragment.height - EditorConfiguration.Gutter.foldMarkerWidth) / 2),
                    width: EditorConfiguration.Gutter.foldMarkerWidth,
                    height: EditorConfiguration.Gutter.foldMarkerWidth
                )
                drawDisclosure(in: frame, collapsed: collapsedFoldRanges.contains(range))
                disclosureFrames.append((frame: frame, range: range))
            }
        }
        drawSeparator(in: dirtyRect, geometry: geometry)
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

    private func notifyWidthChange() {
        onWidthChange?(preferredWidth)
    }

    private func firstLineFragment(for line: EditorGutterMetrics.LogicalSourceLine, in textView: CodeTextView, layoutManager: NSLayoutManager) -> NSRect? {
        let characterCount = (textView.string as NSString).length
        guard let presentationLocation = textView.presentationLocation(forSourceLocation: line.startLocation) else { return nil }
        if presentationLocation == characterCount {
            let extraFragment = layoutManager.extraLineFragmentRect
            return extraFragment.isEmpty ? nil : extraFragment
        }
        guard presentationLocation < characterCount else { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: presentationLocation)
        return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    private func isHidden(line: Int) -> Bool {
        collapsedFoldRanges.contains { line > $0.startLine && line <= $0.endLine }
    }

    private func drawSeparator(in rect: NSRect, geometry: EditorGutterMetrics.GutterGeometry) {
        let separator = NSBezierPath()
        let separatorX = geometry.separatorZone.minX + EditorConfiguration.Gutter.separatorPixelOffset
        separator.move(to: NSPoint(x: separatorX, y: rect.minY))
        separator.line(to: NSPoint(x: separatorX, y: rect.maxY))
        separator.lineWidth = EditorConfiguration.Ruler.lineWidth
        ScopeLightPalette.gutterSeparator.setStroke()
        separator.stroke()
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

final class EditorGutterContainerView: NSView {
    let scrollView: NSScrollView
    let gutterView: EditorGutterView
    private var gutterWidth: CGFloat

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, gutterView: EditorGutterView) {
        self.scrollView = scrollView
        self.gutterView = gutterView
        gutterWidth = gutterView.preferredWidth
        super.init(frame: .zero)
        addSubview(gutterView)
        addSubview(scrollView)
        gutterView.onWidthChange = { [weak self] width in
            guard let self, self.gutterWidth != width else { return }
            self.gutterWidth = width
            self.needsLayout = true
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(x: gutterWidth, y: 0, width: max(0, bounds.width - gutterWidth), height: bounds.height)
    }
}
