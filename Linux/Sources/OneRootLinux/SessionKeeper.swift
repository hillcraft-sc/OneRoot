import Foundation
@testable import OneRoot

/// Reopening the last session's windows and tabs at launch, and saving the
/// current ones (the Linux counterpart of the Mac's `SessionRestorer`).
/// Storage and the safety rules are the shared `SessionService`.
///
/// Saving happens every couple of seconds while anything changed, and at
/// quit, so a crash loses at most a moment. It is skipped until the launch
/// windows are open, and when no window is open (closing the last window
/// quits; the session saved a moment before is the one to keep).
@MainActor
final class SessionKeeper {
    private let service: SessionService
    private var lastSaved: Data?
    private var isReady = false

    init(service: SessionService = SessionService()) {
        self.service = service
    }

    var isEnabled: Bool { service.isEnabled }

    /// The windows to reopen, safe to open today (gone folders replaced by
    /// Home, sizes kept). Empty when the setting is off or nothing is saved.
    func windowsToRestore() -> [SavedWindow] {
        guard let session = service.load() else { return [] }
        let everywhere = CGRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000)
        return SessionService.sanitized(
            session,
            folderExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            fallbackFolder: FileManager.default.homeDirectoryForCurrentUser.path,
            screens: [everywhere]
        ).windows
    }

    /// Allows saving from now on (the launch windows are open).
    func markReady() { isReady = true }

    /// Snapshots `windows` (back to front: the frontmost last).
    func save(_ windows: [AppWindow]) {
        guard isReady, service.isEnabled else { return }
        let open = windows.filter { !$0.viewModel.tabs.isEmpty }
        guard !open.isEmpty else { return }
        let session = SavedSession(windows: open.map { window in
            let width = window.window.width, height = window.window.height
            let frame = width > 0 && height > 0 ? CGRect(x: 0, y: 0, width: width, height: height) : nil
            return window.viewModel.savedState(frame: frame)
        })
        // Skip identical snapshots: this runs on a timer.
        let encoded = try? JSONEncoder().encode(session)
        guard encoded != lastSaved else { return }
        lastSaved = encoded
        service.save(session)
    }

    func setEnabled(_ enabled: Bool) {
        service.setEnabled(enabled)
        lastSaved = nil
    }
}
