import AppKit
import SwiftUI

struct WindowPresentation: NSViewRepresentable {
    let title: String
    let isDocumentEdited: Bool
    let attach: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowObserver {
        WindowObserver()
    }

    func updateNSView(_ view: WindowObserver, context: Context) {
        view.present = { window in
            attach(window)
            window.title = title
            window.isDocumentEdited = isDocumentEdited
        }
        view.updateWindow()
    }

    final class WindowObserver: NSView {
        var present: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }

        func updateWindow() {
            if let window { present?(window) }
        }
    }
}
