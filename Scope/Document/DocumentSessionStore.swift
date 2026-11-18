import Foundation

nonisolated struct RestorableDocument: Codable, Hashable, Identifiable {
    let id: UUID
    let bookmarkData: Data
    let displayPath: String
}

nonisolated struct RestorableDocumentSession: Codable, Equatable {
    var documents: [RestorableDocument]
    var activeDocumentID: UUID?
    var project: RestorableProject? = nil
}

nonisolated struct RestorableProject: Codable, Equatable {
    let bookmarkData: Data
}

struct WorkspaceBookmarks {
    var make: (URL) throws -> Data
    var resolve: (Data) throws -> (url: URL, isStale: Bool)

    static let securityScoped = WorkspaceBookmarks(
        make: { url in
            try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolve: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        }
    )
}

final class DocumentSessionStore {
    private static let storageKey = "openDocumentSession"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RestorableDocumentSession {
        guard let data = defaults.data(forKey: Self.storageKey),
              let session = try? JSONDecoder().decode(RestorableDocumentSession.self, from: data) else {
            return RestorableDocumentSession(documents: [], activeDocumentID: nil)
        }
        return session
    }

    func save(_ session: RestorableDocumentSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
