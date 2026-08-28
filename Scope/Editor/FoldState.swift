import Foundation

struct FoldState {
    private(set) var collapsedRanges = Set<FoldRange>()

    mutating func toggle(_ range: FoldRange) {
        if collapsedRanges.remove(range) == nil {
            collapsedRanges.insert(range)
        }
    }

    mutating func invalidate() {
        collapsedRanges.removeAll()
    }

    mutating func retainOnly(_ availableRanges: [FoldRange]) {
        collapsedRanges.formIntersection(Set(availableRanges))
    }
}
