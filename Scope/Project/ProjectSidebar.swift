import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var project: ProjectContext
    let openFile: (URL) -> Void

    var body: some View {
        List {
            OutlineGroup(project.treeRoots, children: \.children) { node in
                if node.isDirectory {
                    Label(node.name, systemImage: "folder")
                } else {
                    Button {
                        openFile(node.url)
                    } label: {
                        Label(node.name, systemImage: "doc")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(project.rootURL.lastPathComponent)
    }
}
