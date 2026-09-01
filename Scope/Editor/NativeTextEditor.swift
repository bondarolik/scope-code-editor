import AppKit
import SwiftUI

struct HighlightRequest {
    let generation: Int
    let source: String
}

struct HighlightRequestTracker {
    private var currentGeneration = 0

    mutating func makeRequest(for source: String) -> HighlightRequest {
        currentGeneration += 1
        return HighlightRequest(generation: currentGeneration, source: source)
    }

    func accepts(_ request: HighlightRequest, for currentSource: String) -> Bool {
        request.generation == currentGeneration && request.source == currentSource
    }
}

struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var status: EditorStatus
    let language: LanguageID?
    let indentationWidth: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            status: $status,
            language: language,
            indentationWidth: indentationWidth
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textLayoutManager.textContainer = textContainer

        let textView = CodeTextView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400),
            textContainer: textContainer,
            indentationWidth: indentationWidth
        )
        textView.delegate = context.coordinator
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.scheduleHighlight(for: textView)
        context.coordinator.updateStatus(from: textView)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = EditorConfiguration.Text.font
        textView.textContainerInset = NSSize(
            width: EditorConfiguration.Text.horizontalInset,
            height: EditorConfiguration.Text.verticalInset
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        lineNumberRuler.onToggleFold = { [weak textView] range in
            guard let textView else { return }
            context.coordinator.toggleFold(range, in: textView)
        }
        scrollView.verticalRulerView = lineNumberRuler
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }
        textView.string = text
        scrollView.verticalRulerView?.needsDisplay = true
        context.coordinator.updateStatus(from: textView)
        context.coordinator.scheduleHighlight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var status: Binding<EditorStatus>
        private let language: LanguageID?
        private let indentationWidth: Int
        private var highlightRequests = HighlightRequestTracker()
        private var foldRanges = [FoldRange]()
        private var foldState = FoldState()

        init(
            text: Binding<String>,
            status: Binding<EditorStatus>,
            language: LanguageID?,
            indentationWidth: Int
        ) {
            self.text = text
            self.status = status
            self.language = language
            self.indentationWidth = indentationWidth
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
            foldState.invalidate()
            foldRanges = []
            applyFoldPresentation(to: textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
            updateStatus(from: textView)
            textView.needsDisplay = true
            scheduleHighlight(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateStatus(from: textView)
            textView.needsDisplay = true
        }

        func updateStatus(from textView: NSTextView) {
            status.wrappedValue = EditorStatus(
                position: EditorPosition.at(utf16Offset: textView.selectedRange().location, in: textView.string),
                languageName: language?.displayName ?? "Plain Text",
                indentationWidth: indentationWidth
            )
        }

        func scheduleHighlight(for textView: NSTextView) {
            let source = textView.string
            let request = highlightRequests.makeRequest(for: source)
            guard let language else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak textView] in
                let analysis = SyntaxHighlighter.analyze(language: language, source: source)
                DispatchQueue.main.async {
                    guard let self, let textView, self.highlightRequests.accepts(request, for: textView.string) else { return }
                    guard let storage = textView.textStorage else { return }
                    let wholeRange = NSRange(location: 0, length: storage.length)
                    storage.removeAttribute(.foregroundColor, range: wholeRange)
                    for span in analysis.highlightSpans where NSMaxRange(span.range) <= storage.length {
                        storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(for: span.category), range: span.range)
                    }
                    self.foldRanges = analysis.foldRanges
                    self.foldState.retainOnly(analysis.foldRanges)
                    self.applyFoldPresentation(to: textView)
                }
            }
        }

        func toggleFold(_ range: FoldRange, in textView: NSTextView) {
            guard foldRanges.contains(range) else { return }
            let willCollapse = !foldState.collapsedRanges.contains(range)
            if willCollapse,
               let hiddenRange = range.hiddenCharacterRange(in: textView.string),
               NSLocationInRange(textView.selectedRange().location, hiddenRange),
               let start = range.startCharacterLocation(in: textView.string) {
                textView.setSelectedRange(NSRange(location: start, length: 0))
                updateStatus(from: textView)
            }
            foldState.toggle(range)
            applyFoldPresentation(to: textView)
        }

        private func applyFoldPresentation(to textView: NSTextView) {
            guard let codeTextView = textView as? CodeTextView else { return }
            codeTextView.applyFoldPresentation(foldState.collapsedRanges)
            if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
                ruler.foldRanges = foldRanges
                ruler.collapsedFoldRanges = foldState.collapsedRanges
            }
        }

    }
}

private final class CodeTextView: NSTextView {
    private let indentationWidth: Int
    private var collapsedFoldRanges = Set<FoldRange>()

    init(frame frameRect: NSRect, textContainer container: NSTextContainer?, indentationWidth: Int) {
        self.indentationWidth = indentationWidth
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        indentationWidth = EditorConfiguration.defaultIndentationWidth
        super.init(coder: coder)
    }

    override func insertTab(_ sender: Any?) {
        insertText(String(repeating: " ", count: indentationWidth), replacementRange: selectedRange())
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLine(in: rect)
        drawPreferredColumnRuler(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawFoldEllipses(in: dirtyRect)
    }

    func applyFoldPresentation(_ foldedRanges: Set<FoldRange>) {
        guard let layoutManager, let textStorage else { return }
        let wholeRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: wholeRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: wholeRange)
        let collapsedAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: EditorConfiguration.Text.collapsedFontSize, weight: .regular),
            .foregroundColor: NSColor.clear
        ]

        for range in foldedRanges {
            if let hiddenRange = range.hiddenCharacterRange(in: string), NSMaxRange(hiddenRange) <= textStorage.length {
                layoutManager.setTemporaryAttributes(collapsedAttributes, forCharacterRange: hiddenRange)
            }
        }

        collapsedFoldRanges = foldedRanges
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    private func drawCurrentLine(in rect: NSRect) {
        guard let layoutManager, textContainer != nil else { return }
        let characterCount = (string as NSString).length
        let lineRect: NSRect

        if characterCount == 0 || layoutManager.numberOfGlyphs == 0 {
            lineRect = NSRect(
                x: visibleRect.minX,
                y: textContainerOrigin.y,
                width: visibleRect.width,
                height: font?.boundingRectForFont.height ?? EditorConfiguration.Text.font.boundingRectForFont.height
            )
        } else {
            let selectedLocation = selectedRange().location
            let fragment: NSRect
            if selectedLocation == characterCount, !layoutManager.extraLineFragmentRect.isEmpty {
                fragment = layoutManager.extraLineFragmentRect
            } else {
                let location = min(selectedLocation, characterCount - 1)
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
            lineRect = NSRect(
                x: visibleRect.minX,
                y: fragment.minY + textContainerOrigin.y,
                width: visibleRect.width,
                height: fragment.height
            )
        }

        ScopeLightPalette.currentLine.setFill()
        lineRect.intersection(rect).fill()
    }

    private func drawPreferredColumnRuler(in rect: NSRect) {
        let font = font ?? EditorConfiguration.Text.font
        let x = EditorConfiguration.preferredColumnX(textContainerOriginX: textContainerOrigin.x, font: font)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.lineWidth = EditorConfiguration.Ruler.lineWidth
        ScopeLightPalette.preferredColumnRuler.setStroke()
        path.stroke()
    }

    private func drawFoldEllipses(in dirtyRect: NSRect) {
        guard let layoutManager else { return }
        let font = font ?? EditorConfiguration.Text.font
        for range in collapsedFoldRanges {
            guard let location = range.startCharacterLocation(in: string),
                  location < (string as NSString).length else { continue }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
            let fragment = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let point = NSPoint(
                x: fragment.maxX + textContainerOrigin.x + EditorConfiguration.Folding.ellipsisTrailingOffset,
                y: fragment.minY + textContainerOrigin.y
            )
            guard dirtyRect.intersects(NSRect(
                origin: point,
                size: NSSize(width: EditorConfiguration.Folding.ellipsisWidth, height: font.boundingRectForFont.height)
            )) else { continue }
            ("…" as NSString).draw(
                at: point,
                withAttributes: [.font: font, .foregroundColor: ScopeLightPalette.foldEllipsis]
            )
        }
    }
}
