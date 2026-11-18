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
    let collapsedRanges: Set<FoldRange>
    let presentation: String
    let summaries: [Summary]
    private let segments: [Segment]

    init(source: String, collapsedRanges: Set<FoldRange>) {
        self.source = source
        let text = source as NSString
        self.collapsedRanges = collapsedRanges
        let collapsed = collapsedRanges.sorted { lhs, rhs in
            lhs.startLine == rhs.startLine ? lhs.endLine > rhs.endLine : lhs.startLine < rhs.startLine
        }
        var rendered = ""
        var builtSegments = [Segment]()
        var builtSummaries = [Summary]()
        var sourceLocation = 0

        var line = 1
        var lineStart = 0
        var lastFoldEndLine = 0
        func bounds(of target: Int) -> (start: Int, contentsEnd: Int, end: Int)? {
            var end = 0
            var contentsEnd = 0
            while lineStart < text.length {
                text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
                if line == target { return (lineStart, contentsEnd, end) }
                lineStart = end
                line += 1
            }
            return nil
        }

        for foldRange in collapsed {
            guard foldRange.startLine > lastFoldEndLine, foldRange.endLine > foldRange.startLine,
                  let opening = bounds(of: foldRange.startLine), let closing = bounds(of: foldRange.endLine) else { continue }
            lastFoldEndLine = foldRange.endLine
            let hidden = NSRange(location: opening.contentsEnd, length: closing.end - opening.contentsEnd)
            let lineEnding = text.substring(with: NSRange(location: closing.contentsEnd, length: closing.end - closing.contentsEnd))
            let separator = EditorConfiguration.Folding.summarySeparator
            let summaryText = separator + "…" + (foldRange.closingToken.map { separator + $0 } ?? "") + lineEnding

            Self.appendSource(
                NSRange(location: sourceLocation, length: hidden.location - sourceLocation),
                from: text,
                into: &rendered,
                segments: &builtSegments
            )

            let presentationStart = builtSegments.last?.presentationRange.upperBound ?? 0
            rendered += summaryText
            let presentationRange = NSRange(location: presentationStart, length: (summaryText as NSString).length)
            let ellipsisLocation = presentationStart + separator.utf16.count
            let ellipsisRange = NSRange(location: ellipsisLocation, length: ("…" as NSString).length)
            let closingTokenRange = foldRange.closingToken.map {
                NSRange(
                    location: ellipsisRange.upperBound + separator.utf16.count,
                    length: ($0 as NSString).length
                )
            }
            let summary = Summary(
                foldRange: foldRange,
                presentationRange: presentationRange,
                ellipsisRange: ellipsisRange,
                closingTokenRange: closingTokenRange,
                sourceRange: hidden,
                safeSourceLocation: opening.start
            )
            builtSummaries.append(summary)
            builtSegments.append(Segment(sourceRange: hidden, presentationRange: presentationRange, kind: .summary(summary)))
            sourceLocation = hidden.upperBound
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
        if let last = segments.last, location == last.presentationRange.upperBound { return last.sourceRange.upperBound }
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
        if let last = segments.last, location == last.sourceRange.upperBound { return last.presentationRange.upperBound }
        guard let segment = segments.first(where: { NSLocationInRange(location, $0.sourceRange) }) ?? segments.first(where: { location == $0.sourceRange.upperBound }) else {
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
        if source.isEmpty, range == NSRange(location: 0, length: 0) { return range }
        let length = segments.last?.presentationRange.upperBound ?? 0
        guard range.location >= 0, range.length >= 0,
              range.location <= length, range.length <= length - range.location else { return nil }
        // A fold summary is read-only, but an edit may start or end at its visible boundary.
        if range.length == 0, range.location == length {
            return NSRange(location: segments.last?.sourceRange.upperBound ?? 0, length: 0)
        }
        guard let segment = segments.first(where: { segment in
            guard case .source = segment.kind else { return false }
            return range.location >= segment.presentationRange.location && range.upperBound <= segment.presentationRange.upperBound
        }) else {
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
        let presentationStart = segments.last?.presentationRange.upperBound ?? 0
        rendered += text.substring(with: range)
        segments.append(
            Segment(
                sourceRange: range,
                presentationRange: NSRange(location: presentationStart, length: range.length),
                kind: .source
            )
        )
    }
}
