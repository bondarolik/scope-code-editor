import Foundation
import Combine

nonisolated struct ProjectFileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    var id: URL { url }
    var filename: String { url.lastPathComponent }
}

nonisolated enum ProjectIgnorePolicy {
    static let directoryPaths: Set<String> = [".git", "node_modules", "vendor/bundle", "tmp", "log", ".bundle", "coverage", "storage", "public/assets", "public/packs"]

    static func ignores(_ url: URL, relativePath: String, isDirectory: Bool) -> Bool {
        url.lastPathComponent == ".DS_Store" || (isDirectory && directoryPaths.contains(relativePath))
    }
}

nonisolated struct ProjectFileIndex: Sendable {
    let entries: [ProjectFileEntry]
    static let empty = ProjectFileIndex(entries: [])
}

nonisolated struct ProjectTreeNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let children: [ProjectTreeNode]
    var id: URL { url }
}

nonisolated struct ProjectScan: Sendable {
    let fileIndex: ProjectFileIndex
    let treeRoots: [ProjectTreeNode]
}

nonisolated enum ProjectFileIndexer {
    private final class Node {
        let url: URL
        let isDirectory: Bool
        var children: [Node] = []

        init(url: URL, isDirectory: Bool) {
            self.url = url
            self.isDirectory = isDirectory
        }

        func sortedChildren() -> [ProjectTreeNode] {
            children.sorted { first, second in
                if first.isDirectory != second.isDirectory { return first.isDirectory }
                return first.url.lastPathComponent.localizedStandardCompare(second.url.lastPathComponent) == .orderedAscending
            }.map { child in
                ProjectTreeNode(url: child.url, name: child.url.lastPathComponent, isDirectory: child.isDirectory, children: child.sortedChildren())
            }
        }
    }

    static func scan(rootURL: URL) throws -> ProjectScan {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: rootURL])
        }

        let root = Node(url: rootURL, isDirectory: true)
        let rootDepth = rootURL.standardizedFileURL.pathComponents.count
        var directories = [rootURL.standardizedFileURL.path: root]
        var files: [ProjectFileEntry] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let path = url.standardizedFileURL
            let relativePath = path.pathComponents.dropFirst(rootDepth).joined(separator: "/")
            let values = try url.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory == true
            if ProjectIgnorePolicy.ignores(url, relativePath: relativePath, isDirectory: isDirectory) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            guard isDirectory || values.isRegularFile == true else { continue }

            let node = Node(url: url, isDirectory: isDirectory)
            directories[path.deletingLastPathComponent().path]?.children.append(node)
            if isDirectory {
                directories[path.path] = node
            } else {
                files.append(ProjectFileEntry(url: url, relativePath: relativePath))
            }
        }
        if let enumerationError { throw enumerationError }
        try Task.checkCancellation()
        let sortedFiles = files.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        return ProjectScan(fileIndex: ProjectFileIndex(entries: sortedFiles), treeRoots: root.sortedChildren())
    }
}

nonisolated final class ProjectFolderAccess: Sendable {
    let url: URL
    private let accessing: Bool

    init(url: URL) {
        self.url = url
        accessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessing { url.stopAccessingSecurityScopedResource() }
    }
}

@MainActor final class ProjectContext: ObservableObject {
    enum State {
        case scanning
        case loaded(ProjectScan)
        case failed(String)
    }

    let folderAccess: ProjectFolderAccess
    var rootURL: URL { folderAccess.url }
    @Published private(set) var state: State = .scanning
    @Published private(set) var expandedDirectories: Set<URL> = []
    private var scanID: UUID?
    private var scanTask: Task<ProjectScan, Error>?

    var fileIndex: ProjectFileIndex {
        guard case let .loaded(result) = state else { return .empty }
        return result.fileIndex
    }

    init(rootURL: URL) {
        folderAccess = ProjectFolderAccess(url: rootURL)
    }

    @discardableResult
    func buildFileIndex(
        scan: @escaping @Sendable (URL) throws -> ProjectScan = { try ProjectFileIndexer.scan(rootURL: $0) }
    ) -> Task<Void, Never> {
        cancelScan()
        state = .scanning
        let id = UUID()
        scanID = id
        let task = Task.detached(priority: .userInitiated) { [folderAccess] in
            try withExtendedLifetime(folderAccess) { try scan(folderAccess.url) }
        }
        scanTask = task
        return Task { [weak self] in
            let result = await task.result
            guard let self, self.scanID == id else { return }
            self.scanTask = nil
            switch result {
            case .success(let scan): self.state = .loaded(scan)
            case .failure(let error): self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        scanID = nil
        scanTask?.cancel()
        scanTask = nil
    }

    func toggleDirectory(_ url: URL) {
        if expandedDirectories.remove(url) == nil { expandedDirectories.insert(url) }
    }
}
