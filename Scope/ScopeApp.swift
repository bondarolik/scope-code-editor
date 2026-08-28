import AppKit
import SwiftUI

@main
struct ScopeApp: App {
    @StateObject private var document = EditorDocument()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save") {
                    saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(document.fileURL == nil)
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                try document.load(from: url)
            } catch {
                present(error: error, title: "Couldn’t Open File")
            }
        }
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
