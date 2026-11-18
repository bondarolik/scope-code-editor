import Foundation

struct SourceEdit {
    let range: NSRange
    let text: String
}

struct FoldState {
    private var tracked = Set<StructuralFold.Anchors>()
    private var presented = [FoldRange: StructuralFold.Anchors]()

    var collapsedRanges: Set<FoldRange> { Set(presented.keys) }

    mutating func collapse(_ fold: StructuralFold) {
        tracked.insert(fold.anchors)
        presented[fold.range] = fold.anchors
    }

    @discardableResult
    mutating func expand(_ range: FoldRange) -> Bool {
        guard let anchors = presented.removeValue(forKey: range) else { return false }
        tracked.remove(anchors)
        return true
    }

    mutating func reconcile(with folds: [StructuralFold]) {
        guard !tracked.isEmpty else { return }
        let matches = folds.filter { tracked.contains($0.anchors) }
        let uniqueMatches = Dictionary(grouping: matches, by: \.anchors).values.compactMap { group in
            group.count == 1 ? group.first : nil
        }
        tracked = Set(uniqueMatches.map(\.anchors))
        presented = Dictionary(uniqueKeysWithValues: uniqueMatches.map { ($0.range, $0.anchors) })
    }

    mutating func rebase(through edits: [SourceEdit], from source: NSString, to updated: NSString, lineNumberAt: (Int) -> Int?) {
        guard !tracked.isEmpty else { return }
        let changes = edits.compactMap { edit -> (range: NSRange, delta: Int)? in
            let delta = edit.text.utf16.count - edit.range.length
            guard delta != 0 || !source.substring(with: edit.range).utf16.elementsEqual(edit.text.utf16) else { return nil }
            return (edit.range, delta)
        }
        let visible = Dictionary(uniqueKeysWithValues: presented.map { ($0.value, $0.key) })
        var rebased = Set<StructuralFold.Anchors>()
        presented.removeAll(keepingCapacity: true)

        for anchors in tracked {
            guard let opening = Self.translate(anchors.openingToken, through: changes),
                  let closing = Self.translate(anchors.closingLineTail, through: changes) else { continue }
            let next = StructuralFold.Anchors(kind: anchors.kind, openingToken: opening, closingLineTail: closing)
            rebased.insert(next)

            // Leave the fold visible as collapsed only when its hidden text still
            // occupies exactly the same span after translating the edit.
            guard let range = visible[anchors] else { continue }
            var oldOpeningEnd = 0
            source.getLineStart(nil, end: nil, contentsEnd: &oldOpeningEnd, for: anchors.openingToken)
            let hidden = NSRange(location: oldOpeningEnd, length: anchors.closingLineTail.upperBound - oldOpeningEnd)
            guard let shifted = Self.translate(hidden, through: changes) else { continue }
            var openingEnd = 0
            var closingEnd = 0
            updated.getLineStart(nil, end: nil, contentsEnd: &openingEnd, for: opening)
            updated.getLineStart(nil, end: nil, contentsEnd: &closingEnd, for: closing)
            guard shifted.location == openingEnd, shifted.upperBound == closingEnd,
                  let start = lineNumberAt(opening.location), let end = lineNumberAt(closing.location),
                  start < end else { continue }
            presented[FoldRange(startLine: start, endLine: end, closingToken: range.closingToken)] = next
        }
        tracked = rebased
    }

    private static func translate(_ range: NSRange, through changes: [(range: NSRange, delta: Int)]) -> NSRange? {
        var shift = 0
        for change in changes {
            if change.range.upperBound <= range.location {
                shift += change.delta
            } else if change.range.location >= range.upperBound {
                break
            } else {
                return nil
            }
        }
        return NSRange(location: range.location + shift, length: range.length)
    }
}
