import Foundation
import Combine

struct RecentFile: Codable, Hashable, Identifiable {
    let id: UUID
    let bookmarkData: Data
    let displayPath: String
}

final class RecentFileStore: ObservableObject {
    private static let storageKey = "recentFileBookmarks"
    private static let legacyStorageKey = "recentFileURLs"
    private static let maximumCount = 5
    private let defaults: UserDefaults

    @Published private(set) var files: [RecentFile]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: Self.legacyStorageKey)
        if let data = defaults.data(forKey: Self.storageKey),
           let files = try? JSONDecoder().decode([RecentFile].self, from: data) {
            self.files = files
        } else {
            self.files = []
        }
    }

    var mostRecentFile: RecentFile? {
        files.first
    }

    func recordSuccessfulOpen(_ url: URL, replacing file: RecentFile? = nil) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        files.removeAll { $0.displayPath == url.path || $0.id == file?.id }
        files.insert(RecentFile(id: UUID(), bookmarkData: bookmarkData, displayPath: url.path), at: 0)
        if files.count > Self.maximumCount {
            files.removeLast(files.count - Self.maximumCount)
        }
        persist()
    }

    func resolveURL(for file: RecentFile) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: file.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func remove(_ file: RecentFile) {
        files.removeAll { $0.id == file.id }
        persist()
    }

    func menuTitles() -> [(file: RecentFile, title: String)] {
        let duplicateNames = Set(
            Dictionary(grouping: files, by: { URL(fileURLWithPath: $0.displayPath).lastPathComponent })
                .filter { $0.value.count > 1 }
                .map(\.key)
        )

        return files.map { file in
            let url = URL(fileURLWithPath: file.displayPath)
            guard duplicateNames.contains(url.lastPathComponent) else {
                return (file, url.lastPathComponent)
            }
            return (file, "\(url.lastPathComponent) — \(disambiguatingParent(for: file))")
        }
    }

    private func disambiguatingParent(for file: RecentFile) -> String {
        let url = URL(fileURLWithPath: file.displayPath)
        let matches = files.filter {
            URL(fileURLWithPath: $0.displayPath).lastPathComponent == url.lastPathComponent && $0.id != file.id
        }
        let components = url.deletingLastPathComponent().pathComponents

        for count in 1...components.count {
            let suffix = components.suffix(count).joined(separator: "/")
            let isUnique = matches.allSatisfy {
                URL(fileURLWithPath: $0.displayPath).deletingLastPathComponent().pathComponents.suffix(count).joined(separator: "/") != suffix
            }
            if isUnique {
                return suffix
            }
        }

        return url.deletingLastPathComponent().path
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
