import AppKit
import Foundation

enum EditorConfiguration {
    static let preferredColumn = 80
    static let defaultIndentationWidth = 2

    enum Text {
        static let fontSize: CGFloat = 14
        static let lineHeight: CGFloat = 20
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 9

        static var font: NSFont {
            .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    enum Gutter {
        static let lineNumberMinimumDigits = 4
        static let lineNumberLeadingPadding: CGFloat = 4
        static let lineNumberTrailingPadding: CGFloat = 4
        static let foldMarkerGap: CGFloat = 2
        static let foldMarkerZoneWidth: CGFloat = 18
        static let foldMarkerWidth: CGFloat = 12
        static let gutterTrailingPadding: CGFloat = 4
        static let gutterSeparatorWidth: CGFloat = 1
        static let disclosureHitExpansion: CGFloat = 5
        static let separatorPixelOffset: CGFloat = 0.5
        static let collapsedTriangleLeadingInset: CGFloat = 2
        static let collapsedTriangleVerticalInset: CGFloat = 1
        static let expandedTriangleHorizontalInset: CGFloat = 1
        static let expandedTriangleTopInset: CGFloat = 2
        static let currentLineBackgroundAlpha: CGFloat = 0.04

        static var font: NSFont {
            Text.font
        }

        static var horizontalChromeWidth: CGFloat {
            lineNumberLeadingPadding + lineNumberTrailingPadding + foldMarkerGap + foldMarkerZoneWidth + gutterTrailingPadding + gutterSeparatorWidth
        }
    }

    enum StatusBar {
        static let height: CGFloat = 22
        static let horizontalPadding: CGFloat = 10
        static let fieldSpacing: CGFloat = 14
        static let fontSize: CGFloat = 11
        static let separatorHeight: CGFloat = 1
    }

    enum CurrentLine {
        static let accentAlpha: CGFloat = 0.04
    }

    enum Ruler {
        static let lineWidth: CGFloat = 1
        static let separatorAlpha: CGFloat = 0.28
    }

    enum Folding {
        static let summarySeparator = " "
    }

    static func preferredColumnX(textContainerOriginX: CGFloat, font: NSFont) -> CGFloat {
        textContainerOriginX + (font.maximumAdvancement.width * CGFloat(preferredColumn))
    }
}
