import AppKit
import Foundation

enum EditorConfiguration {
    static let preferredColumn = 80
    static let defaultIndentationWidth = 2

    enum Text {
        static let fontSize: CGFloat = 14
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 9
        static let collapsedFontSize: CGFloat = 0.01

        static var font: NSFont {
            .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    enum Gutter {
        static let fontSize: CGFloat = 11
        static let markerZoneWidth: CGFloat = 18
        static let markerWidth: CGFloat = 10
        static let markerToNumberSpacing: CGFloat = 4
        static let numberTrailingPadding: CGFloat = 8
        static let separatorZoneWidth: CGFloat = 1
        static let disclosureHitExpansion: CGFloat = 3
        static let separatorPixelOffset: CGFloat = 0.5
        static let collapsedTriangleLeadingInset: CGFloat = 3
        static let collapsedTriangleVerticalInset: CGFloat = 2
        static let expandedTriangleHorizontalInset: CGFloat = 2
        static let expandedTriangleTopInset: CGFloat = 3

        static var font: NSFont {
            .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        }

        static var horizontalChromeWidth: CGFloat {
            markerZoneWidth + markerToNumberSpacing + numberTrailingPadding + separatorZoneWidth
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
        static let ellipsisTrailingOffset: CGFloat = 4
        static let ellipsisWidth: CGFloat = 12
    }

    static func preferredColumnX(textContainerOriginX: CGFloat, font: NSFont) -> CGFloat {
        textContainerOriginX + (font.maximumAdvancement.width * CGFloat(preferredColumn))
    }
}
