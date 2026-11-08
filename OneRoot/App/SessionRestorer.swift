import AppKit

/// Reopens the last session's windows and tabs at launch, and saves the
/// current ones — see `SessionService` for storage and the Settings toggle.
///
/// Launch: the window SwiftUI opens by itself takes the first saved window
/// (`takeLaunchWindow`); once it's on screen it asks for the rest to be
/// opened (`openRemainingWindows`), each through the same window group a
/// torn-off tab uses, carrying a token `takeWindow` swaps for its saved
/// state. Main windows set `isRestorable = false` (see `WindowAccessor`),
/// so macOS's own restoration never competes with this.
///
/// Saving: every main window registers itself; `saveNow` snapshots them
/// all — on quit, and whenever OneRoot stops being the active app, which
/// also covers the cases quit never sees (a crash, or Stop in Xcode).
@MainActor
final class SessionRestorer {
    static let shared = SessionRestorer()

    private let service: SessionService
    private var didHandOutLaunchWindow = false
    private var remainingWindows: [SavedWindow] = []
    private var pending: [UUID: SavedWindow] = [:]
    /// Not until the launch windows are all open — saving earlier (OneRoot
    /// losing focus mid-launch) would record half a session over the whole one.
    private var isReadyToSave = false

    private final class Entry {
        weak var viewModel: WindowViewModel?
        weak var window: NSWindow?

        init(viewModel: WindowViewModel, window: NSWindow) {
            self.viewModel = viewModel
            self.window = window
        }
    }
    private var entries: [Entry] = []

    /// Unit tests run inside the app (it's their test host). Without this,
    /// every test run would reopen the real saved session, then save the
    /// test host's own windows over it on the way out.
    private let isActive: Bool

    init(service: SessionService = SessionService()) {
        self.service = service
        isActive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    // MARK: Restoring

    /// For the first main window at launch only: the saved window it should
    /// become, `nil` for a fresh window (nothing saved, the setting off, or
    /// a later ⌘N window).
    func takeLaunchWindow() -> SavedWindow? {
        guard !didHandOutLaunchWindow else { return nil }
        didHandOutLaunchWindow = true
        guard isActive, let session = service.load() else { return nil }
        let windows = SessionService.sanitized(
            session,
            folderExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            fallbackFolder: FileManager.default.homeDirectoryForCurrentUser.path,
            screens: NSScreen.screens.map(\.visibleFrame)
        ).windows
        remainingWindows = Array(windows.dropFirst())
        return windows.first
    }

    /// Opens the rest of the saved windows, via `open` (the launch window's
    /// `openWindow`), and from then on allows saving.
    func openRemainingWindows(_ open: (UUID) -> Void) {
        for window in remainingWindows {
            let token = UUID()
            pending[token] = window
            open(token)
        }
        remainingWindows = []
        isReadyToSave = true
    }

    func takeWindow(_ token: UUID) -> SavedWindow? {
        pending.removeValue(forKey: token)
    }

    // MARK: Saving

    func register(_ viewModel: WindowViewModel, window: NSWindow) {
        entries.removeAll { $0.window == nil || $0.window === window }
        entries.append(Entry(viewModel: viewModel, window: window))
    }

    func saveNow() {
        guard isActive, isReadyToSave, service.isEnabled else { return }
        // `orderedWindows` runs front to back; saved back to front, so the
        // window that was in front reopens last, on top.
        let zOrder = NSApp.orderedWindows
        let open = entries.compactMap { entry -> (WindowViewModel, NSWindow)? in
            guard let viewModel = entry.viewModel, let window = entry.window,
                  window.isVisible || window.isMiniaturized,
                  !viewModel.tabs.isEmpty else { return nil }
            return (viewModel, window)
        }
        let backToFront = open.sorted { a, b in
            (zOrder.firstIndex(of: a.1) ?? .max) > (zOrder.firstIndex(of: b.1) ?? .max)
        }
        service.save(SavedSession(windows: backToFront.map { viewModel, window in
            viewModel.savedState(frame: window.frame)
        }))
    }
}
