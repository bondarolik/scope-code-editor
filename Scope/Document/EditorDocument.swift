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
    @Published private(set) var indentationWidth = EditorConfiguration.defaultIndentationWidth
    @Published private(set) var presentationGeneration = 0
    private var savedText = ""

    @Published private(set) var isDirty = false

    var windowTitle: String {
        fileURL?.lastPathComponent ?? "Scope"
    }

    private func updateDirtyState() {
        isDirty = text != savedText
    }

    struct LoadedDocument {
        let url: URL
        let text: String
        let indentationWidth: Int
    }

    func prepareLoad(from url: URL) throws -> LoadedDocument {
        let data = try Data(contentsOf: url)
        guard let decodedText = String(data: data, encoding: .utf8) else {
            throw EditorDocumentError.unsupportedTextEncoding
        }

        return LoadedDocument(
            url: url,
            text: decodedText,
            indentationWidth: IndentationDetector.width(in: decodedText)
        )
    }

    func activate(_ loadedDocument: LoadedDocument) {
        fileURL = loadedDocument.url
        text = loadedDocument.text
        indentationWidth = loadedDocument.indentationWidth
        savedText = loadedDocument.text
        isDirty = false
        presentationGeneration += 1
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
