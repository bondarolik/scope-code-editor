import AppKit
import SwiftUI

struct WindowPresentation: NSViewRepresentable {
    let title: String
    let isDocumentEdited: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.title = title
            view.window?.isDocumentEdited = isDocumentEdited
        }
    }
}
