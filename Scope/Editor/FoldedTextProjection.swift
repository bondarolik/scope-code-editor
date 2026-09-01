import Foundation

struct FoldedTextProjection {
    struct Summary {
        let foldRange: FoldRange
        let presentationRange: NSRange
        let ellipsisRange: NSRange
        let closingTokenRange: NSRange?
        let sourceRange: NSRange
        let safeSourceLocation: Int
    }

    private enum SegmentKind {
        case source
        case summary(Summary)
    }

    private struct Segment {
        let sourceRange: NSRange
        let presentationRange: NSRange
        let kind: SegmentKind
    }

    let source: String
    let presentation: String
    let summaries: [Summary]
    private let segments: [Segment]

    init(source: String, collapsedRanges: Set<FoldRange>) {
        self.source = source
        let text = source as NSString
        let collapsed = Self.outermostCollapsedRanges(collapsedRanges, in: source)
        var rendered = ""
        var builtSegments = [Segment]()
        var builtSummaries = [Summary]()
        var sourceLocation = 0

        for foldRange in collapsed {
            guard let replacement = foldRange.presentationReplacement(in: source),
                  replacement.sourceRange.location >= sourceLocation else { continue }

            Self.appendSource(
                NSRange(location: sourceLocation, length: replacement.sourceRange.location - sourceLocation),
                from: text,
                into: &rendered,
                segments: &builtSegments
            )

            let presentationStart = (rendered as NSString).length
            rendered += replacement.text
            let presentationRange = NSRange(location: presentationStart, length: (replacement.text as NSString).length)
            let ellipsisLocation = presentationStart + replacement.leadingSeparatorLength
            let ellipsisRange = NSRange(location: ellipsisLocation, length: ("…" as NSString).length)
            let closingTokenRange = replacement.closingToken.map {
                NSRange(
                    location: ellipsisRange.upperBound + replacement.interTokenSeparatorLength,
                    length: ($0 as NSString).length
                )
            }
            let summary = Summary(
                foldRange: foldRange,
                presentationRange: presentationRange,
                ellipsisRange: ellipsisRange,
                closingTokenRange: closingTokenRange,
                sourceRange: replacement.sourceRange,
                safeSourceLocation: replacement.safeSourceLocation
            )
            builtSummaries.append(summary)
            builtSegments.append(Segment(sourceRange: replacement.sourceRange, presentationRange: presentationRange, kind: .summary(summary)))
            sourceLocation = replacement.sourceRange.upperBound
        }

        Self.appendSource(
            NSRange(location: sourceLocation, length: text.length - sourceLocation),
            from: text,
            into: &rendered,
            segments: &builtSegments
        )

        presentation = rendered
        summaries = builtSummaries
        segments = builtSegments
    }

    func sourceLocation(forPresentationLocation location: Int) -> Int {
        guard let segment = segments.first(where: { NSLocationInRange(location, $0.presentationRange) }) ?? segments.first(where: { location == $0.presentationRange.upperBound }) else {
            return (source as NSString).length
        }
        switch segment.kind {
        case .source:
            return segment.sourceRange.location + min(location - segment.presentationRange.location, segment.sourceRange.length)
        case let .summary(summary):
            return summary.safeSourceLocation
        }
    }

    func presentationLocation(forSourceLocation location: Int) -> Int? {
        guard let segment = segments.first(where: { NSLocationInRange(location, $0.sourceRange) || location == $0.sourceRange.upperBound }) else {
            return nil
        }
        switch segment.kind {
        case .source:
            return segment.presentationRange.location + min(location - segment.sourceRange.location, segment.presentationRange.length)
        case let .summary(summary):
            return summary.presentationRange.location
        }
    }

    func editableSourceRange(forPresentationRange range: NSRange) -> NSRange? {
        guard !summaries.contains(where: {
            range.location >= $0.presentationRange.location && range.location <= $0.presentationRange.upperBound
        }) else {
            return nil
        }
        guard let segment = segments.first(where: {
            range.location >= $0.presentationRange.location && range.upperBound <= $0.presentationRange.upperBound
        }), case .source = segment.kind else {
            return nil
        }
        return NSRange(
            location: segment.sourceRange.location + (range.location - segment.presentationRange.location),
            length: range.length
        )
    }

    func sourceRange(coveringPresentationRange range: NSRange) -> NSRange {
        let overlapping = segments.filter { NSIntersectionRange($0.presentationRange, range).length > 0 }
        guard let first = overlapping.first, let last = overlapping.last else {
            let location = sourceLocation(forPresentationLocation: range.location)
            return NSRange(location: location, length: 0)
        }
        return NSRange(location: first.sourceRange.location, length: last.sourceRange.upperBound - first.sourceRange.location)
    }

    func presentationRanges(forSourceRange range: NSRange) -> [NSRange] {
        segments.compactMap { segment in
            guard case .source = segment.kind else { return nil }
            let intersection = NSIntersectionRange(segment.sourceRange, range)
            guard intersection.length > 0 else { return nil }
            return NSRange(
                location: segment.presentationRange.location + (intersection.location - segment.sourceRange.location),
                length: intersection.length
            )
        }
    }

    private static func appendSource(
        _ range: NSRange,
        from text: NSString,
        into rendered: inout String,
        segments: inout [Segment]
    ) {
        guard range.length > 0 else { return }
        let presentationStart = (rendered as NSString).length
        let fragment = text.substring(with: range)
        rendered += fragment
        segments.append(
            Segment(
                sourceRange: range,
                presentationRange: NSRange(location: presentationStart, length: (fragment as NSString).length),
                kind: .source
            )
        )
    }

    private static func outermostCollapsedRanges(_ ranges: Set<FoldRange>, in source: String) -> [FoldRange] {
        ranges.sorted { lhs, rhs in
            lhs.startLine == rhs.startLine ? lhs.endLine > rhs.endLine : lhs.startLine < rhs.startLine
        }.filter { candidate in
            !ranges.contains { enclosing in
                enclosing.startLine < candidate.startLine && enclosing.endLine >= candidate.endLine
            }
        }
    }
}

private extension FoldRange {
    struct PresentationReplacement {
        let sourceRange: NSRange
        let text: String
        let leadingSeparatorLength: Int
        let interTokenSeparatorLength: Int
        let closingToken: String?
        let safeSourceLocation: Int
    }

    func presentationReplacement(in source: String) -> PresentationReplacement? {
        let text = source as NSString
        guard startLine >= 1, endLine > startLine, text.length > 0 else { return nil }

        var line = 1
        var location = 0
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        var openingContentsEnd: Int?
        var openingStart: Int?

        while location < text.length {
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            if line == startLine {
                openingContentsEnd = contentsEnd
                openingStart = lineStart
            }
            if line == endLine, let openingContentsEnd, let openingStart {
                let preservedLineEnding = text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
                let separator = EditorConfiguration.Folding.summarySeparator
                let summary = separator + "…" + (closingToken.map { separator + $0 } ?? "") + preservedLineEnding
                return PresentationReplacement(
                    sourceRange: NSRange(location: openingContentsEnd, length: lineEnd - openingContentsEnd),
                    text: summary,
                    leadingSeparatorLength: (separator as NSString).length,
                    interTokenSeparatorLength: closingToken == nil ? 0 : (separator as NSString).length,
                    closingToken: closingToken,
                    safeSourceLocation: openingStart
                )
            }
            location = lineEnd
            line += 1
        }
        return nil
    }
}
