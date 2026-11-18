import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var project: ProjectContext
    let activeFileURL: URL?
    let openFile: (URL) -> Void

    var body: some View {
        List {
            ForEach(project.treeRoots) { node in
                ProjectTreeRow(node: node, project: project, activeFileURL: activeFileURL, openFile: openFile)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ProjectTreeRow: View {
    let node: ProjectTreeNode
    @ObservedObject var project: ProjectContext
    let activeFileURL: URL?
    let openFile: (URL) -> Void
    var depth = 0

    var body: some View {
        if node.isDirectory {
            Button { toggleDirectory() } label: {
                Label(node.name, systemImage: project.expandedDirectories.contains(node.url) ? "chevron.down" : "chevron.right")
                    .padding(.leading, CGFloat(depth) * 14)
            }
            .buttonStyle(.plain)
            if project.expandedDirectories.contains(node.url) {
                ForEach(node.children ?? []) { child in
                    ProjectTreeRow(node: child, project: project, activeFileURL: activeFileURL, openFile: openFile, depth: depth + 1)
                }
            }
        } else {
            Button { openFile(node.url) } label: {
                Label(node.name, systemImage: "doc")
                    .padding(.leading, CGFloat(depth) * 14)
            }
            .buttonStyle(.plain)
            .listRowBackground(node.url == activeFileURL ? Color.accentColor.opacity(0.14) : Color.clear)
        }
    }

    private func toggleDirectory() {
        if project.expandedDirectories.contains(node.url) { project.expandedDirectories.remove(node.url) }
        else { project.expandedDirectories.insert(node.url) }
    }
}
