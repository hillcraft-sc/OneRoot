import AppKit

/// Main reason for a full `NSApplicationDelegate`: intercepting Quit while
/// a file operation — compress/extract, or now also copy/move — is still
/// running. A subprocess like `ditto`/`7z` isn't tied to OneRoot's own
/// process lifetime (it gets reparented, not killed, when the parent
/// quits), and an in-flight copy/move `Task` would simply be abandoned
/// mid-item — so without this, "quit while busy" silently leaves work
/// running or half-done with no owner.
///
/// Also saves the session (windows and tabs, see `SessionRestorer`) on quit
/// and whenever OneRoot stops being the active app, and hooks file
/// operations up to VoiceOver announcements.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // VoiceOver hears when a copy, move, compress, … finishes, is
        // cancelled, or fails — said once for the app, not per window.
        FileOperationProgressCenter.shared.announce = { text in
            NSAccessibility.post(
                element: NSApp.mainWindow ?? NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionRestorer.shared.saveNow()
    }

    func applicationDidResignActive(_ notification: Notification) {
        SessionRestorer.shared.saveNow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hasRunningArchiveProcess = ArchiveProcessRegistry.shared.hasRunningProcesses
        let hasRunningFileOperation = !FileOperationProgressCenter.shared.operations.isEmpty
        guard hasRunningArchiveProcess || hasRunningFileOperation else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "A file operation is still running"
        alert.informativeText = "Quitting now will stop it partway through — anything being copied, compressed, or extracted may be incomplete."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        ArchiveProcessRegistry.shared.terminateAll()
        for operation in FileOperationProgressCenter.shared.operations {
            operation.cancel()
        }
        return .terminateNow
    }
}
