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
        if !textView.canonicalSource.utf16.elementsEqual(text.utf16) {
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
        private struct Replacement {
            let range: NSRange
            let text: String
        }

        private struct PendingEdit {
            let replacements: [Replacement]
            let selection: NSRange
        }

        private var pendingEdit: PendingEdit?
        private let editorUndoManager = UndoManager()
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

        func attach(to textView: CodeTextView) {
            textView.delegate = self
            // AppKit still performs input, but its presentation ranges never enter this undo manager.
            textView.allowsUndo = false
            textView.sourceUndoManager = editorUndoManager
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

        func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
            pendingEdit = nil
            guard let replacementStrings else { return true }
            guard let view = textView as? CodeTextView, affectedRanges.count == replacementStrings.count else { return false }
            if view.isComposing { return true }

            let source = view.canonicalSource as NSString
            var replacements: [Replacement] = []
            for (range, replacement) in zip(affectedRanges, replacementStrings) {
                guard let sourceRange = view.editableSourceRange(forPresentationRange: range.rangeValue),
                      source.isUTF16Boundary(sourceRange.location), source.isUTF16Boundary(sourceRange.upperBound) else { return false }
                replacements.append(Replacement(range: sourceRange, text: replacement))
            }
            pendingEdit = PendingEdit(replacements: replacements, selection: view.sourceSelection)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? CodeTextView, !view.isApplyingProjection,
                  !view.isComposing, let edit = pendingEdit else { return }
            pendingEdit = nil
            apply(edit.replacements, restoring: edit.selection, selecting: nil, in: view)
        }

        fileprivate func commitComposition(_ replacement: String, in range: NSRange, restoring selection: NSRange, from view: CodeTextView) {
            apply([Replacement(range: range, text: replacement)], restoring: selection, selecting: nil, in: view)
        }

        private func apply(
            _ replacements: [Replacement],
            restoring previousSelection: NSRange,
            selecting nextSelection: NSRange?,
            in view: CodeTextView
        ) {
            let source = view.canonicalSource as NSString
            var inverse: [Replacement] = []
            var delta = 0
            var end = 0
            for replacement in replacements {
                let range = replacement.range
                guard range.location >= end, range.location <= source.length,
                      range.length >= 0, range.length <= source.length - range.location,
                      source.isUTF16Boundary(range.location), source.isUTF16Boundary(range.upperBound) else { return }
                let insertedLength = replacement.text.utf16.count
                inverse.append(Replacement(
                    range: NSRange(location: range.location + delta, length: insertedLength),
                    text: source.substring(with: range)
                ))
                delta += insertedLength - range.length
                end = range.upperBound
            }
            guard let last = inverse.last else { return }
            let updated = NSMutableString(string: source as String)
            for replacement in replacements.reversed() {
                updated.replaceCharacters(in: replacement.range, with: replacement.text)
            }
            let newSource = updated as String
            guard !newSource.utf16.elementsEqual(view.canonicalSource.utf16) else { return }

            let selection = nextSelection ?? NSRange(location: last.range.upperBound, length: 0)
            editorUndoManager.registerUndo(withTarget: self) { [weak view] coordinator in
                guard let view else { return }
                coordinator.apply(inverse, restoring: selection, selecting: previousSelection, in: view)
            }
            synchronizeSource(newSource, selection: selection, in: view)
        }

        private func synchronizeSource(_ updatedSource: String, selection: NSRange, in textView: CodeTextView) {
            text.wrappedValue = updatedSource
            foldState.invalidate()
            foldRanges = []
            highlightSpans = []
            applyFoldPresentation(to: textView, source: updatedSource, selection: selection)
            gutter(for: textView)?.updateSourceText(updatedSource)
            updateSelection(from: textView)
            scheduleHighlight(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView,
                  !textView.isApplyingProjection, !textView.isComposing else { return }
            updateSelection(from: textView)
        }

        private func updateSelection(from textView: CodeTextView) {
            updateStatus(from: textView)
            textView.needsDisplay = true
            gutter(for: textView)?.needsDisplay = true
            let caret = textView.sourceSelection.location
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
            let sourceLocation = (textView as? CodeTextView)?.sourceSelection.location ?? textView.selectedRange().location
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
            guard let view = textView as? CodeTextView, !view.isComposing, foldRanges.contains(range) else { return }
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

        private func applyFoldPresentation(to textView: NSTextView, source: String? = nil, selection: NSRange? = nil) {
            guard let codeTextView = textView as? CodeTextView, !codeTextView.isComposing else { return }
            codeTextView.applyProjection(
                source: source ?? codeTextView.canonicalSource,
                collapsedRanges: foldState.collapsedRanges,
                sourceSelection: selection
            )
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
    fileprivate(set) weak var sourceUndoManager: UndoManager?
    private(set) var projection = FoldedTextProjection(source: "", collapsedRanges: [])
    private(set) var isApplyingProjection = false

    private struct Composition {
        let presentationRange: NSRange
        let sourceRange: NSRange
        let selection: NSRange
    }

    private var composition: Composition?
    private var isHandlingTextInput = false

    var canonicalSource: String { projection.source }
    var foldedSummaries: [FoldedTextProjection.Summary] { projection.summaries }
    var isComposing: Bool { composition != nil }

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

    @objc(undo:) func undoSourceEdit(_ sender: Any?) {
        if isComposing { unmarkText() }
        sourceUndoManager?.undo()
    }

    @objc(redo:) func redoSourceEdit(_ sender: Any?) {
        if isComposing { unmarkText() }
        sourceUndoManager?.redo()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if composition == nil {
            let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
            guard let sourceRange = editableSourceRange(forPresentationRange: range) else { return }
            composition = Composition(presentationRange: range, sourceRange: sourceRange, selection: sourceSelection)
        }
        handleTextInput { super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange) }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        handleTextInput { super.insertText(string, replacementRange: replacementRange) }
    }

    override func unmarkText() {
        handleTextInput { super.unmarkText() }
    }

    private func handleTextInput(_ input: () -> Void) {
        let wasHandlingInput = isHandlingTextInput
        isHandlingTextInput = true
        input()
        isHandlingTextInput = wasHandlingInput
        if !wasHandlingInput, !hasMarkedText(), let composition {
            self.composition = nil
            finishComposition(composition)
        }
    }

    private func finishComposition(_ composition: Composition) {
        let original = projection.presentation as NSString
        let presented = string as NSString
        let start = composition.presentationRange.location
        let suffixLength = original.length - composition.presentationRange.upperBound
        // The marked text can change length repeatedly. Only its original visible span may be committed.
        guard presented.length >= start + suffixLength,
              original.substring(to: start).utf16.elementsEqual(presented.substring(to: start).utf16),
              original.substring(from: composition.presentationRange.upperBound).utf16.elementsEqual(
                  presented.substring(from: presented.length - suffixLength).utf16
              ) else {
            applyProjection(source: canonicalSource, collapsedRanges: Set(foldedSummaries.map(\.foldRange)), sourceSelection: composition.selection)
            return
        }
        let replacement = presented.substring(with: NSRange(location: start, length: presented.length - start - suffixLength))
        (delegate as? NativeTextEditor.Coordinator)?.commitComposition(replacement, in: composition.sourceRange, restoring: composition.selection, from: self)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        canPerformHistoryAction(menuItem.action) ?? super.validateMenuItem(menuItem)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        canPerformHistoryAction(item.action) ?? super.validateUserInterfaceItem(item)
    }

    private func canPerformHistoryAction(_ action: Selector?) -> Bool? {
        switch action {
        case #selector(undoSourceEdit(_:)): return sourceUndoManager?.canUndo ?? false
        case #selector(redoSourceEdit(_:)): return sourceUndoManager?.canRedo ?? false
        default: return nil
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLine(in: rect)
        drawPreferredColumnRuler(in: rect)
    }

    var sourceSelection: NSRange {
        let selection = selectedRange()
        if let visible = editableSourceRange(forPresentationRange: selection) { return visible }
        let start = sourceLocation(forPresentationLocation: selection.location)
        let end = sourceLocation(forPresentationLocation: selection.upperBound)
        return NSRange(location: start, length: max(0, end - start))
    }

    func applyProjection(source: String, collapsedRanges: Set<FoldRange>, sourceSelection: NSRange? = nil) {
        let selection = sourceSelection ?? self.sourceSelection
        projection = FoldedTextProjection(source: source, collapsedRanges: collapsedRanges)
        isApplyingProjection = true
        let shouldReplaceText = !string.utf16.elementsEqual(projection.presentation.utf16)
        if shouldReplaceText { string = projection.presentation }
        if shouldReplaceText || sourceSelection != nil {
            let length = source.utf16.count
            let start = projection.presentationLocation(forSourceLocation: min(selection.location, length)) ?? 0
            let end = projection.presentationLocation(forSourceLocation: min(selection.upperBound, length)) ?? start
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

private extension NSString {
    func isUTF16Boundary(_ offset: Int) -> Bool {
        offset == 0 || offset == length || !(0xDC00...0xDFFF).contains(character(at: offset))
    }
}
