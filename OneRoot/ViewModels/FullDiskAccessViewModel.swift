import AppKit
import Combine

/// Drives the Full Disk Access onboarding screen. Rechecks automatically
/// whenever the app becomes active, so coming back from System
/// Settings after granting access dismisses the screen without the user
/// having to click anything (on macOS versions where FDA takes effect
/// without a relaunch — otherwise the explainer's "relaunch" instruction
/// covers it).
@MainActor
@Observable
final class FullDiskAccessViewModel {
    private(set) var hasAccess: Bool

    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        hasAccess = FullDiskAccessChecker.hasAccess()
        cancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.recheck() }
    }

    func recheck() {
        hasAccess = FullDiskAccessChecker.hasAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
