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
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
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
        scrollView.verticalRulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
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
                let spans = SyntaxHighlighter.spans(for: language, source: source)
                DispatchQueue.main.async {
                    guard let self, let textView, self.highlightRequests.accepts(request, for: textView.string) else { return }
                    guard let storage = textView.textStorage else { return }
                    let wholeRange = NSRange(location: 0, length: storage.length)
                    storage.removeAttribute(.foregroundColor, range: wholeRange)
                    for span in spans where NSMaxRange(span.range) <= storage.length {
                        storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(for: span.category), range: span.range)
                    }
                }
            }
        }

    }
}

private final class CodeTextView: NSTextView {
    private let indentationWidth: Int

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

    private func drawCurrentLine(in rect: NSRect) {
        guard let layoutManager, textContainer != nil else { return }
        let characterCount = (string as NSString).length
        let lineRect: NSRect

        if characterCount == 0 || layoutManager.numberOfGlyphs == 0 {
            lineRect = NSRect(
                x: visibleRect.minX,
                y: textContainerOrigin.y,
                width: visibleRect.width,
                height: font?.boundingRectForFont.height ?? 16
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

        NSColor.controlAccentColor.withAlphaComponent(0.055).setFill()
        lineRect.intersection(rect).fill()
    }

    private func drawPreferredColumnRuler(in rect: NSRect) {
        let font = font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let x = textContainerOrigin.x + (font.maximumAdvancement.width * CGFloat(EditorConfiguration.preferredColumn))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.lineWidth = 1
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.stroke()
    }
}
