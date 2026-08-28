import SwiftUI

struct EditorStatus: Equatable {
    var position = EditorPosition.beginning
    var languageName = "Plain Text"
    var indentationWidth = EditorConfiguration.defaultIndentationWidth
}

struct EditorStatusBar: View {
    let status: EditorStatus

    var body: some View {
        HStack(spacing: 16) {
            Text("Line \(status.position.line), Column \(status.position.column)")
            Spacer()
            Text(status.languageName)
            Text("Spaces: \(status.indentationWidth)")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }
}
