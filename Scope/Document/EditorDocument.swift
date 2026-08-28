import Foundation
import Combine

enum EditorDocumentError: LocalizedError, Equatable {
    case noOpenFile
    case unsupportedTextEncoding

    var errorDescription: String? {
        switch self {
        case .noOpenFile:
            "There is no open file to save."
        case .unsupportedTextEncoding:
            "Scope currently supports UTF-8 text files only."
        }
    }
}

final class EditorDocument: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var text = ""
    private var savedText = ""

    @Published private(set) var isDirty = false

    var windowTitle: String {
        fileURL?.lastPathComponent ?? "Scope"
    }

    private func updateDirtyState() {
        isDirty = text != savedText
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let decodedText = String(data: data, encoding: .utf8) else {
            throw EditorDocumentError.unsupportedTextEncoding
        }

        fileURL = url
        text = decodedText
        savedText = decodedText
        isDirty = false
    }

    func updateText(_ newText: String) {
        text = newText
        updateDirtyState()
    }

    func save() throws {
        guard let fileURL else {
            throw EditorDocumentError.noOpenFile
        }

        guard let data = text.data(using: .utf8) else {
            throw EditorDocumentError.unsupportedTextEncoding
        }
        try data.write(to: fileURL, options: .atomic)
        savedText = text
        isDirty = false
    }
}
