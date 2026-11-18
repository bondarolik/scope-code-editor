import AppKit

struct WorkspaceCloseGate {
    enum Request: Equatable { case window, quit }

    private(set) var pending: Request?
    private(set) var windowCloseApproved = false

    mutating func begin(_ request: Request) -> Bool {
        guard pending == nil, !windowCloseApproved else { return false }
        pending = request
        return true
    }

    mutating func finish(_ request: Request, approved: Bool) {
        guard pending == request else { return }
        pending = nil
        windowCloseApproved = request == .window && approved
    }

    mutating func resetWindowApproval() {
        windowCloseApproved = false
    }
}

final class ScopeApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var session: EditorSession?
    private(set) weak var workspaceWindow: NSWindow?
    private var windowDelegate: WorkspaceWindowDelegate?
    private var closeGate = WorkspaceCloseGate()

    func attach(_ window: NSWindow, session: EditorSession) {
        self.session = session
        workspaceWindow = window
        if let windowDelegate, window.delegate === windowDelegate { return }
        let delegate = WorkspaceWindowDelegate(original: window.delegate, applicationDelegate: self)
        windowDelegate = delegate
        window.delegate = delegate
    }

    func shouldCloseWorkspace(_ window: NSWindow) -> Bool {
        guard let session else { return true }
        guard closeGate.begin(.window) else { return false }
        Task { @MainActor in
            session.confirmCloseAll(in: window) { approved in
                self.closeGate.finish(.window, approved: approved)
                if approved {
                    // Closing the workspace ends this session, including any open Settings window.
                    NSApp.terminate(window)
                    self.closeGate.resetWindowApproval()
                }
            }
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if closeGate.windowCloseApproved { return .terminateNow }
        guard closeGate.pending == nil else { return .terminateCancel }
        guard let session, session.hasDirtyDocuments || session.isConfirmingClose else { return .terminateNow }
        guard closeGate.begin(.quit) else { return .terminateCancel }
        // Reply after AppKit has received terminateLater, even if confirmation completes immediately.
        Task { @MainActor in
            session.confirmCloseAll(in: workspaceWindow) { approved in
                self.closeGate.finish(.quit, approved: approved)
                sender.reply(toApplicationShouldTerminate: approved)
            }
        }
        return .terminateLater
    }
}

private final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {
    private weak var original: (any NSWindowDelegate)?
    private weak var applicationDelegate: ScopeApplicationDelegate?

    init(original: (any NSWindowDelegate)?, applicationDelegate: ScopeApplicationDelegate) {
        self.original = original
        self.applicationDelegate = applicationDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        applicationDelegate?.shouldCloseWorkspace(sender) ?? true
    }

    // Keep SwiftUI's delegate handling for the other AppKit window events.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if let original, original.responds(to: selector) { return original }
        return super.forwardingTarget(for: selector)
    }
}
