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
    @Binding var caretSourceOffset: Int
    @Binding var navigationTarget: Int?
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            status: $status,
            language: language,
            indentationWidth: indentationWidth,
            caretSourceOffset: $caretSourceOffset,
            navigationTarget: $navigationTarget
        )
    }

    func makeNSView(context: Context) -> EditorGutterContainerView {
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
        textView.applyProjection(source: text, collapsedRanges: [])
        let caret = min(max(0, caretSourceOffset), text.utf16.count)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        context.coordinator.attach(to: textView)
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
        let gutterView = EditorGutterView(scrollView: scrollView, textView: textView)
        gutterView.onToggleFold = { [weak textView] range in
            guard let textView else { return }
            context.coordinator.toggleFold(range, in: textView)
        }
        context.coordinator.scheduleHighlight(for: textView)
        context.coordinator.updateStatus(from: textView)
        return EditorGutterContainerView(scrollView: scrollView, gutterView: gutterView)
    }

    func updateNSView(_ containerView: EditorGutterContainerView, context: Context) {
        let scrollView = containerView.scrollView
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        if textView.canonicalSource != text {
            textView.applyProjection(source: text, collapsedRanges: [])
            containerView.gutterView.updateSourceText(text)
            context.coordinator.updateStatus(from: textView)
            context.coordinator.scheduleHighlight(for: textView)
        }
        context.coordinator.updateActivation(isActive, in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var status: Binding<EditorStatus>
        private let language: LanguageID?
        private let indentationWidth: Int
        private var caretSourceOffset: Binding<Int>
        private var navigationTarget: Binding<Int?>
        private var highlightRequests = HighlightRequestTracker()
        private var foldRanges = [FoldRange]()
        private var foldState = FoldState()
        private var highlightSpans = [HighlightSpan]()
        private var pendingSourceEdit: (range: NSRange, replacement: String)?
        private let editorUndoManager = UndoManager()
        private weak var textView: CodeTextView?
        private var isActive = false

        init(
            text: Binding<String>,
            status: Binding<EditorStatus>,
            language: LanguageID?,
            indentationWidth: Int,
            caretSourceOffset: Binding<Int>,
            navigationTarget: Binding<Int?>
        ) {
            self.text = text
            self.status = status
            self.language = language
            self.indentationWidth = indentationWidth
            self.caretSourceOffset = caretSourceOffset
            self.navigationTarget = navigationTarget
        }

        func undoManager(for view: NSTextView) -> UndoManager? { editorUndoManager }

        func attach(to textView: CodeTextView) {
            self.textView = textView
            textView.delegate = self
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                NotificationCenter.default.addObserver(self, selector: #selector(didReplayUndo(_:)), name: name, object: editorUndoManager)
            }
            for name in [Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
                NotificationCenter.default.addObserver(self, selector: #selector(willReplayUndo(_:)), name: name, object: editorUndoManager)
            }
        }

        @objc private func willReplayUndo(_ notification: Notification) {
            guard let textView, !textView.foldedSummaries.isEmpty else { return }
            foldState.invalidate()
            applyFoldPresentation(to: textView)
        }

        @objc private func didReplayUndo(_ notification: Notification) {
            guard let textView, textView.foldedSummaries.isEmpty else { return }
            pendingSourceEdit = nil
            synchronizeSource(textView.string, in: textView)
        }

        func updateActivation(_ active: Bool, in textView: CodeTextView) {
            let becameActive = active && !isActive
            isActive = active
            guard active, becameActive || navigationTarget.wrappedValue != nil else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, self.isActive, let textView else { return }
                if becameActive { textView.window?.makeFirstResponder(textView) }
                self.applyNavigationTarget(to: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView, !textView.isApplyingProjection else { return }
            let edit = pendingSourceEdit
            pendingSourceEdit = nil
            if textView.foldedSummaries.isEmpty {
                synchronizeSource(textView.string, in: textView)
            } else if let edit {
                let source = (textView.canonicalSource as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                synchronizeSource(source, in: textView)
                // AppKit recorded this edit in folded coordinates that no longer match the buffer.
                // Wait for AppKit to finish its current undo group before clearing it.
                DispatchQueue.main.async { [weak self] in self?.editorUndoManager.removeAllActions() }
            }
        }

        private func synchronizeSource(_ updatedSource: String, in textView: CodeTextView) {
            guard updatedSource != textView.canonicalSource else { return }
            text.wrappedValue = updatedSource
            textView.applyProjection(source: updatedSource, collapsedRanges: [])
            gutter(for: textView)?.updateSourceText(updatedSource)
            foldState.invalidate()
            foldRanges = []
            highlightSpans = []
            applyFoldPresentation(to: textView)
            updateSelection(from: textView)
            scheduleHighlight(for: textView)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let codeTextView = textView as? CodeTextView,
                  let sourceRange = codeTextView.editableSourceRange(forPresentationRange: affectedCharRange) else {
                return false
            }
            pendingSourceEdit = (sourceRange, replacementString ?? "")
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView, !textView.isApplyingProjection else { return }
            updateSelection(from: textView)
        }

        private func updateSelection(from textView: CodeTextView) {
            updateStatus(from: textView)
            textView.needsDisplay = true
            gutter(for: textView)?.needsDisplay = true
            let caret = textView.sourceLocation(forPresentationLocation: textView.selectedRange().location)
            if caretSourceOffset.wrappedValue != caret { caretSourceOffset.wrappedValue = caret }
        }

        private func applyNavigationTarget(to textView: CodeTextView) {
            guard let target = navigationTarget.wrappedValue else { return }
            navigationTarget.wrappedValue = nil
            guard let presentation = textView.presentationLocation(forSourceLocation: target) else { return }
            textView.setSelectedRange(NSRange(location: presentation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: presentation, length: 0))
            if caretSourceOffset.wrappedValue != target { caretSourceOffset.wrappedValue = target }
        }

        func updateStatus(from textView: NSTextView) {
            let sourceLocation = (textView as? CodeTextView)?.sourceLocation(forPresentationLocation: textView.selectedRange().location) ?? textView.selectedRange().location
            let newStatus = EditorStatus(
                position: EditorPosition.at(utf16Offset: sourceLocation, in: (textView as? CodeTextView)?.canonicalSource ?? textView.string),
                languageName: language?.displayName ?? "Plain Text",
                indentationWidth: indentationWidth
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.status.wrappedValue != newStatus else { return }
                self.status.wrappedValue = newStatus
            }
        }

        func scheduleHighlight(for textView: NSTextView) {
            let source = (textView as? CodeTextView)?.canonicalSource ?? textView.string
            let request = highlightRequests.makeRequest(for: source)
            guard let language else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak textView] in
                let analysis = SyntaxHighlighter.analyze(language: language, source: source)
                DispatchQueue.main.async {
                    guard let self, let textView,
                          let codeTextView = textView as? CodeTextView,
                          self.highlightRequests.accepts(request, for: codeTextView.canonicalSource) else { return }
                    self.foldRanges = analysis.foldRanges
                    self.foldState.retainOnly(analysis.foldRanges)
                    self.highlightSpans = analysis.highlightSpans
                    self.applyFoldPresentation(to: textView)
                }
            }
        }

        func toggleFold(_ range: FoldRange, in textView: NSTextView) {
            guard foldRanges.contains(range) else { return }
            let willCollapse = !foldState.collapsedRanges.contains(range)
            if willCollapse,
               let sourceLocation = (textView as? CodeTextView)?.sourceLocation(forPresentationLocation: textView.selectedRange().location),
               let hiddenRange = range.hiddenCharacterRange(in: (textView as? CodeTextView)?.canonicalSource ?? textView.string),
               NSLocationInRange(sourceLocation, hiddenRange),
               let start = range.startCharacterLocation(in: (textView as? CodeTextView)?.canonicalSource ?? textView.string),
               let presentationStart = (textView as? CodeTextView)?.presentationLocation(forSourceLocation: start) {
                textView.setSelectedRange(NSRange(location: presentationStart, length: 0))
                updateStatus(from: textView)
            }
            foldState.toggle(range)
            applyFoldPresentation(to: textView)
        }

        private func applyFoldPresentation(to textView: NSTextView) {
            guard let codeTextView = textView as? CodeTextView else { return }
            codeTextView.applyProjection(source: codeTextView.canonicalSource, collapsedRanges: foldState.collapsedRanges)
            applyHighlighting(highlightSpans, to: codeTextView)
            if let gutter = gutter(for: textView) {
                gutter.foldRanges = foldRanges
                gutter.collapsedFoldRanges = foldState.collapsedRanges
            }
        }

        private func gutter(for textView: NSTextView) -> EditorGutterView? {
            (textView.enclosingScrollView?.superview as? EditorGutterContainerView)?.gutterView
        }

        private func applyHighlighting(_ spans: [HighlightSpan], to textView: CodeTextView) {
            guard let storage = textView.textStorage else { return }
            let wholeRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.foregroundColor, range: wholeRange)
            for span in spans {
                for range in textView.presentationRanges(forSourceRange: span.range) {
                    storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(for: span.category), range: range)
                }
            }
            for summary in textView.foldedSummaries {
                storage.addAttribute(.foregroundColor, value: ScopeLightPalette.foldEllipsis, range: summary.ellipsisRange)
                if let closingRange = summary.closingTokenRange {
                    storage.addAttribute(.foregroundColor, value: ScopeLightPalette.keyword, range: closingRange)
                }
            }
        }

    }
}

final class CodeTextView: NSTextView {
    private let indentationWidth: Int
    private(set) var projection = FoldedTextProjection(source: "", collapsedRanges: [])
    private(set) var isApplyingProjection = false

    var canonicalSource: String { projection.source }
    var foldedSummaries: [FoldedTextProjection.Summary] { projection.summaries }

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

    func applyProjection(source: String, collapsedRanges: Set<FoldRange>) {
        let selection = selectedRange()
        let sourceStart = projection.sourceLocation(forPresentationLocation: selection.location)
        let sourceEnd = projection.sourceLocation(forPresentationLocation: NSMaxRange(selection))
        projection = FoldedTextProjection(source: source, collapsedRanges: collapsedRanges)
        isApplyingProjection = true
        undoManager?.disableUndoRegistration()
        if string != projection.presentation {
            string = projection.presentation
            let start = projection.presentationLocation(forSourceLocation: sourceStart) ?? 0
            let end = projection.presentationLocation(forSourceLocation: sourceEnd) ?? start
            setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = EditorConfiguration.Text.lineHeight
        paragraphStyle.maximumLineHeight = EditorConfiguration.Text.lineHeight
        textStorage?.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: (projection.presentation as NSString).length)
        )
        undoManager?.enableUndoRegistration()
        isApplyingProjection = false
        needsDisplay = true
        (enclosingScrollView?.superview as? EditorGutterContainerView)?.gutterView.needsDisplay = true
    }

    func sourceLocation(forPresentationLocation location: Int) -> Int {
        projection.sourceLocation(forPresentationLocation: location)
    }

    func presentationLocation(forSourceLocation location: Int) -> Int? {
        projection.presentationLocation(forSourceLocation: location)
    }

    func editableSourceRange(forPresentationRange range: NSRange) -> NSRange? {
        projection.editableSourceRange(forPresentationRange: range)
    }

    func presentationRanges(forSourceRange range: NSRange) -> [NSRange] {
        projection.presentationRanges(forSourceRange: range)
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

}
