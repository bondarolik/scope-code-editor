import SwiftUI

struct DocumentBar: View {
    let documents: [EditorDocument]
    let activeDocument: EditorDocument?
    let activate: (EditorDocument) -> Void
    let close: (EditorDocument) -> Void

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(documents) { document in
                        DocumentTab(
                            document: document,
                            title: DocumentTabTitle.title(for: document, among: documents),
                            isActive: document === activeDocument,
                            activate: { activate(document) },
                            close: { close(document) }
                        )
                        .id(document.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onAppear {
                if let id = activeDocument?.id { scroll.scrollTo(id) }
            }
            .onChange(of: activeDocument?.id) { id in
                if let id { scroll.scrollTo(id) }
            }
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct DocumentTab: View {
    @ObservedObject var document: EditorDocument
    let title: String
    let isActive: Bool
    let activate: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: activate) {
                HStack(spacing: 5) {
                    if document.isDirty {
                        Circle().frame(width: 5, height: 5)
                    }
                    Text(title).lineLimit(1)
                }
                .padding(.leading, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Close \(document.windowTitle)")
            .accessibilityLabel("Close \(document.windowTitle)")
        }
        .font(.system(size: 12))
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(isActive ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
    }
}

enum DocumentTabTitle {
    static func title(for document: EditorDocument, among documents: [EditorDocument]) -> String {
        guard let url = document.fileURL,
              documents.filter({ $0.windowTitle == document.windowTitle }).count > 1 else { return document.windowTitle }
        return "\(document.windowTitle) — \(url.deletingLastPathComponent().lastPathComponent)"
    }
}
