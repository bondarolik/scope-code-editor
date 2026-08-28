import Foundation

enum IndentationDetector {
    private static let supportedWidths = [2, 4, 8]
    private static let maximumLinesToInspect = 500

    static func width(in source: String) -> Int {
        let indentationWidths = source
            .split(whereSeparator: \.isNewline)
            .prefix(maximumLinesToInspect)
            .compactMap { line -> Int? in
                guard line.contains(where: { !$0.isWhitespace }) else { return nil }
                let spaces = line.prefix(while: { $0 == " " }).count
                guard spaces > 0, line.first != "\t" else { return nil }
                return spaces
            }

        guard let first = indentationWidths.first else {
            return EditorConfiguration.defaultIndentationWidth
        }

        let commonWidth = indentationWidths.dropFirst().reduce(first, greatestCommonDivisor)
        return supportedWidths.contains(commonWidth)
            ? commonWidth
            : EditorConfiguration.defaultIndentationWidth
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}
