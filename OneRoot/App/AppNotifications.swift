import Foundation

/// Posted by Advanced Search results to reach whichever main window should
/// act on them — see `RevealInOneRootRequest`.
extension Notification.Name {
    static let revealInOneRoot = Notification.Name("\(AppConfig.bundleIdentifier).revealInOneRoot")
    /// Settings ▸ General changed how dates are shown (Date Last Opened's
    /// source, or Today/Yesterday): lists reload to show it.
    static let fileListDatesChanged = Notification.Name("\(AppConfig.bundleIdentifier).fileListDatesChanged")
}

/// Payload for `.revealInOneRoot`, posted as the notification's `object`.
/// `MainWindowFocusTracker` decides which open main window (if more than
/// one) should act on it; `MainWindowView` then either navigates its active
/// tab or opens a new one, per `openInNewTab`.
struct RevealInOneRootRequest {
    let url: URL
    let openInNewTab: Bool
}
