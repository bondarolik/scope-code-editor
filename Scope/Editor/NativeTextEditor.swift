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
    let language: LanguageID?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textLayoutManager.textContainer = textContainer

        let textView = CodeTextView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400),
            textContainer: textContainer
        )
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.scheduleHighlight(for: textView)
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
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private let language: LanguageID?
        private var highlightRequests = HighlightRequestTracker()

        init(text: Binding<String>, language: LanguageID?) {
            self.text = text
            self.language = language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
            scheduleHighlight(for: textView)
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
    override func insertTab(_ sender: Any?) {
        insertText("  ", replacementRange: selectedRange())
    }
}
