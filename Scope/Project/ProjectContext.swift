import Foundation
import Combine

struct ProjectFileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    var id: URL { url }
    var filename: String { url.lastPathComponent }
}

enum ProjectIgnorePolicy {
    static let directoryPaths: Set<String> = [".git", "node_modules", "vendor/bundle", "tmp", "log", ".bundle", "coverage", "storage", "public/assets", "public/packs"]
    static func ignores(_ url: URL, relativePath: String, isDirectory: Bool) -> Bool {
        let name = url.lastPathComponent
        return name == ".DS_Store" || (isDirectory && directoryPaths.contains(relativePath))
    }
}

struct ProjectFileIndex: Sendable {
    let entries: [ProjectFileEntry]
    static let empty = ProjectFileIndex(entries: [])
}

struct ProjectTreeNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let children: [ProjectTreeNode]?
    var id: URL { url }
}

enum ProjectTreeBuilder {
    private final class MutableNode {
        let url: URL; let name: String; let isDirectory: Bool
        var children = [String: MutableNode]()
        init(url: URL, name: String, isDirectory: Bool) { self.url = url; self.name = name; self.isDirectory = isDirectory }
        func frozen() -> ProjectTreeNode {
            let nodes = children.values.sorted { $0.isDirectory == $1.isDirectory ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.isDirectory }.map { $0.frozen() }
            return ProjectTreeNode(url: url, name: name, isDirectory: isDirectory, children: isDirectory ? nodes : nil)
        }
    }
    static func roots(from index: ProjectFileIndex, rootURL: URL) -> [ProjectTreeNode] {
        let root = MutableNode(url: rootURL, name: rootURL.lastPathComponent, isDirectory: true)
        for entry in index.entries {
            var parent = root
            for (offset, component) in entry.relativePath.split(separator: "/").map(String.init).enumerated() {
                let isFile = offset == entry.relativePath.split(separator: "/").count - 1
                if let existing = parent.children[component] { parent = existing } else {
                    let child = MutableNode(url: parent.url.appendingPathComponent(component), name: component, isDirectory: !isFile)
                    parent.children[component] = child; parent = child
                }
            }
        }
        return root.children.values.sorted { $0.isDirectory == $1.isDirectory ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.isDirectory }.map { $0.frozen() }
    }
}

enum ProjectFileIndexer {
    static func build(rootURL: URL) -> ProjectFileIndex {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else { return .empty }
        var entries = [ProjectFileEntry]()
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let values = try? url.resourceValues(forKeys: keys)
            let directory = values?.isDirectory == true
            if ProjectIgnorePolicy.ignores(url, relativePath: relative, isDirectory: directory) {
                if directory { enumerator.skipDescendants() }
                continue
            }
            if values?.isRegularFile == true { entries.append(.init(url: url, relativePath: relative)) }
        }
        return ProjectFileIndex(entries: entries.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending })
    }
}

@MainActor final class ProjectContext: ObservableObject {
    let rootURL: URL
    private let accessesSecurityScope: Bool
    @Published private(set) var fileIndex = ProjectFileIndex.empty
    @Published private(set) var treeRoots = [ProjectTreeNode]()
    init(rootURL: URL) { self.rootURL = rootURL; accessesSecurityScope = rootURL.startAccessingSecurityScopedResource() }
    deinit { if accessesSecurityScope { rootURL.stopAccessingSecurityScopedResource() } }
    func buildFileIndex() {
        let root = rootURL
        Task.detached(priority: .userInitiated) {
            let index = ProjectFileIndexer.build(rootURL: root)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.fileIndex = index
                self.treeRoots = ProjectTreeBuilder.roots(from: index, rootURL: self.rootURL)
            }
        }
    }
}
