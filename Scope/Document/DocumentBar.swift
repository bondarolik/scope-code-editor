import SwiftUI

struct DocumentBar: View {
    let documents: [EditorDocument]
    let activeDocument: EditorDocument?
    let activate: (EditorDocument) -> Void
    let close: (EditorDocument) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(documents) { document in
                    Button { activate(document) } label: {
                        HStack(spacing: 5) {
                            if document.isDirty {
                                Circle().frame(width: 5, height: 5)
                            }
                            Text(DocumentTabTitle.title(for: document, among: documents))
                                .lineLimit(1)
                            Button { close(document) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .help("Close \(document.windowTitle)")
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(document === activeDocument ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DocumentTabTitle.title(for: document, among: documents))
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

}

enum DocumentTabTitle {
    static func title(for document: EditorDocument, among documents: [EditorDocument]) -> String {
        guard let url = document.fileURL,
              documents.filter({ $0.windowTitle == document.windowTitle }).count > 1 else { return document.windowTitle }
        return "\(document.windowTitle) — \(url.deletingLastPathComponent().lastPathComponent)"
    }
}
