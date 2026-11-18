import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var project: ProjectContext
    let activeFileURL: URL?
    let openFile: (URL) -> Void

    var body: some View {
        switch project.state {
        case .scanning:
            ProgressView("Scanning project…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Couldn’t Read Project")
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let scan):
            List(visibleRows(scan.treeRoots)) { row in
                Button {
                    if row.node.isDirectory { project.toggleDirectory(row.node.url) }
                    else { openFile(row.node.url) }
                } label: {
                    Label(row.node.name, systemImage: symbol(for: row.node))
                        .padding(.leading, CGFloat(row.depth) * 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(isActive(row.node) ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .listStyle(.sidebar)
        }
    }

    private struct Row: Identifiable {
        let node: ProjectTreeNode
        let depth: Int
        var id: URL { node.id }
    }

    private func visibleRows(_ nodes: [ProjectTreeNode], depth: Int = 0) -> [Row] {
        var rows: [Row] = []
        for node in nodes {
            rows.append(Row(node: node, depth: depth))
            if project.expandedDirectories.contains(node.url) {
                rows.append(contentsOf: visibleRows(node.children, depth: depth + 1))
            }
        }
        return rows
    }

    private func symbol(for node: ProjectTreeNode) -> String {
        guard node.isDirectory else { return "doc" }
        return project.expandedDirectories.contains(node.url) ? "chevron.down" : "chevron.right"
    }

    private func isActive(_ node: ProjectTreeNode) -> Bool {
        !node.isDirectory && node.url.standardizedFileURL == activeFileURL?.standardizedFileURL
    }
}
