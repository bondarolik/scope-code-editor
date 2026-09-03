import AppKit
import SwiftUI

@main
struct ScopeApp: App {
    @StateObject private var document = EditorDocument()
    @StateObject private var recentFiles = RecentFileStore()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    chooseFileToOpen()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Last Used") {
                    openLastUsed()
                }
                .disabled(recentFiles.mostRecentFile == nil)

                Menu("Open Recent") {
                    ForEach(recentFiles.menuTitles(), id: \.file) { item in
                        Button(item.title) {
                            openRecentFile(item.file)
                        }
                    }
                }
                .disabled(recentFiles.files.isEmpty)

                Divider()

                Button("Save") {
                    saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(document.fileURL == nil)
            }
        }
    }

    private func chooseFileToOpen() {
        let panel = NSOpenPanel()
        panel.title = "Open File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            requestOpen(url)
        }
    }

    private func openLastUsed() {
        guard let file = recentFiles.mostRecentFile else { return }
        openRecentFile(file)
    }

    private func openRecentFile(_ file: RecentFile) {
        do {
            let url = try recentFiles.resolveURL(for: file)
            requestOpen(url, recentFile: file)
        } catch {
            recentFiles.remove(file)
            present(error: error, title: "Couldn’t Open File")
        }
    }

    private func requestOpen(_ url: URL, recentFile: RecentFile? = nil) {
        guard url.isFileURL else { return }
        guard document.isDirty else {
            openDocument(url, recentFile: recentFile)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn:
                do {
                    try document.save()
                    openDocument(url, recentFile: recentFile)
                } catch {
                    present(error: error, title: "Couldn’t Save File")
                }
            case .alertSecondButtonReturn:
                openDocument(url, recentFile: recentFile)
            default:
                break
            }
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func openDocument(_ url: URL, recentFile: RecentFile?) {
        do {
            let loadedDocument = try document.prepareLoad(from: url)
            document.activate(loadedDocument)
            recentFiles.recordSuccessfulOpen(url, replacing: recentFile)
        } catch {
            if let recentFile, isMissingFileError(error) {
                recentFiles.remove(recentFile)
            }
            present(error: error, title: "Couldn’t Open File")
        }
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == CocoaError.fileNoSuchFile.rawValue
    }

    private func saveFile() {
        do {
            try document.save()
        } catch {
            present(error: error, title: "Couldn’t Save File")
        }
    }

    private func present(error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }
}
