import AppKit

/// Confirms before closing a window's last tab (⌘W or the tab bar's own
/// close button) — closing it also closes the window, and it's easy to hit
/// the same trigger that closes an ordinary tab without meaning to lose the
/// whole window. Lives at the UI layer, not `WindowViewModel`, for the same
/// reason as `TrashConfirmation`: a blocking `NSAlert` inside the view model
/// would hang `WindowViewModelTests`, which closes tabs (including the only
/// one) directly. Can be turned off entirely from Settings → General.
enum CloseLastTabConfirmation {
    private static let preferenceService = CloseLastTabPreferenceService()

    /// `true` means proceed with closing the tab (and, with it, the window).
    static func confirm() -> Bool {
        guard preferenceService.shouldWarn else { return true }
        let alert = NSAlert()
        alert.messageText = "Close This Window?"
        alert.informativeText = "This is the last tab. Closing it will also close the window."
        alert.addButton(withTitle: "Close Window")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
