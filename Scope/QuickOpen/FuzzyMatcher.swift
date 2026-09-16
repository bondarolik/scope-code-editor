import Foundation

enum FuzzyMatcher {
    static func ranked(_ query: String, entries: [ProjectFileEntry]) -> [ProjectFileEntry] {
        let words: [String] = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        // Map entries to (score, entry) pairs, filtering out nil scores
        let scored: [(Int, ProjectFileEntry)] = entries.compactMap { entry in
            if let s = score(words, entry) {
                return (s, entry)
            } else {
                return nil
            }
        }

        // Sort by score descending, then by shorter relativePath when scores tie
        let sorted: [(Int, ProjectFileEntry)] = scored.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1.relativePath.count < rhs.1.relativePath.count
            } else {
                return lhs.0 > rhs.0
            }
        }

        // Extract the entries
        let result: [ProjectFileEntry] = sorted.map { $0.1 }
        return result
    }
    private static func score(_ words: [String], _ entry: ProjectFileEntry) -> Int? {
        guard !words.isEmpty else { return 0 }
        let path = entry.relativePath.lowercased(), name = entry.filename.lowercased()
        var result = 0
        for word in words {
            if name == word { result += 1000; continue }
            if name.hasPrefix(word) { result += 700; continue }
            if let range = path.range(of: word) { result += 450 - path.distance(from: path.startIndex, to: range.lowerBound); continue }
            var cursor = path.startIndex; var gaps = 0
            for character in word { guard let hit = path[cursor...].firstIndex(of: character) else { return nil }; gaps += path.distance(from: cursor, to: hit); cursor = path.index(after: hit) }
            result += max(50, 250 - gaps)
        }
        return result
    }
}
