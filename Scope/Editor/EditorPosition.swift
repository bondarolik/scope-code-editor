import Foundation

struct EditorPosition: Equatable {
    let line: Int
    let column: Int

    static let beginning = EditorPosition(line: 1, column: 1)

    static func at(utf16Offset: Int, in source: String) -> EditorPosition {
        let index = stringIndex(atUTF16Offset: utf16Offset, in: source)
        let prefix = source[..<index]
        let line = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let lineStart = prefix.lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        let column = source[lineStart..<index].count + 1
        return EditorPosition(line: line, column: column)
    }

    private static func stringIndex(atUTF16Offset offset: Int, in source: String) -> String.Index {
        let boundedOffset = min(max(0, offset), source.utf16.count)
        var candidate = boundedOffset

        while candidate > 0 {
            let utf16Index = source.utf16.index(source.utf16.startIndex, offsetBy: candidate)
            if let index = String.Index(utf16Index, within: source) {
                return index
            }
            candidate -= 1
        }

        return source.startIndex
    }
}
