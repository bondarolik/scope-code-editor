import Foundation

struct RestorableDocument: Codable, Hashable, Identifiable {
    let id: UUID
    let bookmarkData: Data
    let displayPath: String
}

struct RestorableDocumentSession: Codable, Equatable {
    var documents: [RestorableDocument]
    var activeDocumentID: UUID?
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

    static func document(for url: URL) -> RestorableDocument? {
        guard let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        return RestorableDocument(id: UUID(), bookmarkData: bookmarkData, displayPath: url.path)
    }

    static func resolveURL(for document: RestorableDocument) throws -> URL {
        var isStale = false
        return try URL(resolvingBookmarkData: document.bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}
