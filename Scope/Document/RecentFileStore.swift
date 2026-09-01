import Foundation
import Combine

final class RecentFileStore: ObservableObject {
    private static let storageKey = "recentFileURLs"
    private static let maximumCount = 5
    private let defaults: UserDefaults

    @Published private(set) var urls: [URL]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urls = (defaults.stringArray(forKey: Self.storageKey) ?? []).compactMap { URL(fileURLWithPath: $0) }
    }

    var mostRecentURL: URL? {
        urls.first
    }

    func recordSuccessfulOpen(_ url: URL) {
        guard url.isFileURL else { return }
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url, at: 0)
        if urls.count > Self.maximumCount {
            urls.removeLast(urls.count - Self.maximumCount)
        }
        persist()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persist()
    }

    func menuTitles() -> [(url: URL, title: String)] {
        let duplicateNames = Set(
            Dictionary(grouping: urls, by: \.lastPathComponent)
                .filter { $0.value.count > 1 }
                .map(\.key)
        )

        return urls.map { url in
            guard duplicateNames.contains(url.lastPathComponent) else {
                return (url, url.lastPathComponent)
            }
            return (url, "\(url.lastPathComponent) — \(disambiguatingParent(for: url))")
        }
    }

    private func disambiguatingParent(for url: URL) -> String {
        let matches = urls.filter {
            $0.lastPathComponent == url.lastPathComponent && $0.standardizedFileURL != url.standardizedFileURL
        }
        let components = url.deletingLastPathComponent().pathComponents

        for count in 1...components.count {
            let suffix = components.suffix(count).joined(separator: "/")
            let isUnique = matches.allSatisfy {
                $0.deletingLastPathComponent().pathComponents.suffix(count).joined(separator: "/") != suffix
            }
            if isUnique {
                return suffix
            }
        }

        return url.deletingLastPathComponent().path
    }

    private func persist() {
        defaults.set(urls.map(\.path), forKey: Self.storageKey)
    }
}
