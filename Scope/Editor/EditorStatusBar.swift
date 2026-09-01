import SwiftUI

struct EditorStatus: Equatable {
    var position = EditorPosition.beginning
    var languageName = "Plain Text"
    var indentationWidth = EditorConfiguration.defaultIndentationWidth
}

struct EditorStatusBar: View {
    let status: EditorStatus

    var body: some View {
        HStack(spacing: EditorConfiguration.StatusBar.fieldSpacing) {
            Text("Line \(status.position.line), Column \(status.position.column)")
            Spacer()
            Text(status.languageName)
            Text("Spaces: \(status.indentationWidth)")
        }
        .font(.system(size: EditorConfiguration.StatusBar.fontSize))
        .foregroundStyle(Color(nsColor: ScopeLightPalette.statusText))
        .padding(.horizontal, EditorConfiguration.StatusBar.horizontalPadding)
        .frame(height: EditorConfiguration.StatusBar.height)
        .background(Color(nsColor: ScopeLightPalette.statusBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: ScopeLightPalette.statusSeparator))
                .frame(height: EditorConfiguration.StatusBar.separatorHeight)
        }
    }
}
