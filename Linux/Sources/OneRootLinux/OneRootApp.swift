import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The application: its windows, app-wide actions, and the shared core's
/// hooks into this UI (questions, notices, the clipboard).
@MainActor
final class OneRootApp {
    static let id = "com.hillcraft_sc.OneRoot"

    let application = Application(id: OneRootApp.id, flags: GApplicationFlags(rawValue: 1 << 2)) // G_APPLICATION_HANDLES_OPEN: newer glibs import the flag names differently
    private(set) var windows: [AppWindow] = []

    init() {
        application.onStartup { [weak self] in self?.startup() }
        application.onActivate { [weak self] in self?.activate() }
        application.onOpen { [weak self] urls, _ in
            guard let self else { return }
            // Opened with files: those are the launch, not the last session.
            if !self.didLaunch { self.didLaunch = true; self.sessionKeeper.markReady() }
            for url in urls {
                var isDirectory: ObjCBool = false
                let folder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    ? url : url.deletingLastPathComponent()
                if let window = self.windows.last, !self.windows.isEmpty {
                    window.newTab(at: folder)
                    window.window.present()
                } else {
                    self.openWindow(at: folder)
                }
            }
        }
    }

    let sessionKeeper = SessionKeeper()

    /// Linux releases are tagged `linux-v<version>` in the shared releases repo.
    static let updateCenter: UpdateCenter = {
        var checker = UpdateChecker()
        checker.channel = .linux
        return UpdateCenter(checker: checker, currentVersion: AppVersion.current)
    }()
    private var updateWatch: ObservationWatch?

    /// First activation reopens the last session's windows; later ones
    /// (launching again) open a plain window.
    private var didLaunch = false
    private func activate() {
        guard !didLaunch else { openWindow(); return }
        didLaunch = true
        let saved = windows.isEmpty ? sessionKeeper.windowsToRestore() : []
        if saved.isEmpty {
            if windows.isEmpty { openWindow() }
        } else {
            for window in saved { openWindow(restoring: window) }
        }
        sessionKeeper.markReady()
    }

    func run() -> Int {
        application.run()
    }

    private func startup() {
        let css = CSSProvider()
        css.loadFromString(Style.css + ChartPalette.css)
        css.addToDefaultDisplay()
        cssProvider = css
        themeController = ThemeController()
        startSavingPreferences()

        installPlatformHooks()

        // Tarball installs only (package managers update the others): at most
        // one automatic check a day, if the user turned it on.
        if InstallMethod.current.checksForUpdates {
            let center = Self.updateCenter
            updateWatch = ObservationWatch.watch({ center.presentRequestCount }) { [weak self] count in
                guard count > 0, case .available(let release) = center.state else { return }
                self?.windows.last?.showToast("OneRoot \(release.version) is available. See Settings \u{25B8} General \u{25B8} Updates.")
            }
            center.checkAutomaticallyIfDue()
        }

        let newWindow = SimpleAction(name: "new-window") { [weak self] in self?.openWindow() }
        application.addAction(newWindow)
        application.setAccelerators(["<Control>n"], for: "app.new-window")
        let quit = SimpleAction(name: "quit") { [weak self] in self?.requestQuit() }
        FileOperationProgressCenter.shared.announce = { [weak self] text in self?.activeWindow?.showToast(text) }
        application.addAction(quit)
        application.setAccelerators(["<Control>q"], for: "app.quit")
        let settingsAction = SimpleAction(name: "settings") { [weak self] in self?.openSettings() }
        application.addAction(settingsAction)
        application.setAccelerators(["<Control>comma"], for: "app.settings")
        let help = SimpleAction(name: "help") { [weak self] in self?.openHelp() }
        application.addAction(help)
        application.setAccelerators(["F1"], for: "app.help")
        let shortcuts = SimpleAction(name: "shortcuts") { [weak self] in
            guard let self else { return }
            if let window = self.activeWindow {
                ShortcutsPopover.show(from: window.pathBar.widget) { [weak self] in self?.openHelp(topic: .shortcuts) }
            } else {
                self.openHelp(topic: .shortcuts)
            }
        }
        application.addAction(shortcuts)
        application.setAccelerators(["<Control>question", "<Control>F1"], for: "app.shortcuts")
        let about = SimpleAction(name: "about") { [weak self] in self?.showAbout() }
        application.addAction(about)
    }

    private var cssProvider: CSSProvider?
    private(set) var themeController: ThemeController?
    private var settings: SettingsDialog?

    /// The window in front, for dialogs the shared core asks for.
    var activeWindow: AppWindow? {
        windows.first { $0.window.isActive } ?? windows.last
    }

    /// Where the core's confirmations and errors attach: the Find Duplicates
    /// window while it has focus (it trashes files itself), else the active
    /// file window.
    private var dialogParent: Widget? {
        if let duplicates, duplicates.window.isActive { return duplicates.window }
        return activeWindow?.window
    }

    /// The shared core's questions and notices, and the desktop's
    /// clipboard — set before any view model is made.
    /// GdkPixbuf, qpdf and Cairo/Pango behind Quick Actions.
    static let quickActionServices = QuickActionServices(
        images: LinuxImageTransformService(), pdfs: LinuxPDFCombineService(), documents: LinuxDocumentPDFConverter()
    )

    private func installPlatformHooks() {
        if let clipboard = DesktopClipboard() { Platform.clipboard = clipboard }
        QuickActionServices.current = Self.quickActionServices
        Platform.confirmTrashHandler = { [weak self] names in
            let heading = names.count == 1 ? "Move \u{201C}\(names[0])\u{201D} to the Trash?" : "Move \(names.count) Items to the Trash?"
            let body = names.count == 1 ? "You can restore it from the Trash later." : "You can restore them from the Trash later."
            let dialog = Dialogs.alert(heading: heading, body: body, responses: [("cancel", "Cancel"), ("trash", "Move to Trash")],
                                       destructive: "trash", defaultResponse: "trash")
            return Dialogs.runModal(dialog, parent: self?.dialogParent) == "trash"
        }
        Platform.confirmDeleteWithoutTrashHandler = { [weak self] urls in
            let heading = urls.count == 1
                ? "\u{201C}\(urls[0].lastPathComponent)\u{201D} Can't Go to the Trash"
                : "\(urls.count) Items Can't Go to the Trash"
            let body = "The drive \(urls.count == 1 ? "it's" : "they're") on has no Trash (common for network shares and some removable drives). Delete \(urls.count == 1 ? "it" : "them") permanently? This can't be undone."
            let dialog = Dialogs.alert(heading: heading, body: body, responses: [("cancel", "Cancel"), ("delete", "Delete Permanently")],
                                       destructive: "delete")
            return Dialogs.runModal(dialog, parent: self?.dialogParent) == "delete"
        }
        Platform.showErrorHandler = { [weak self] title, message in
            Dialogs.showError(title, message, parent: self?.dialogParent)
        }
    }

    private var advancedSearch: AdvancedSearchWindow?

    /// The Advanced Search window (one): opened, or brought forward. With
    /// `criteria` (Search Subfolders) it starts that search; otherwise it
    /// searches from `folder`.
    func openAdvancedSearch(handing criteria: SearchCriteria? = nil, from folder: URL? = nil) {
        if advancedSearch == nil {
            let search = AdvancedSearchWindow(
                application: application,
                root: folder ?? FileManager.default.homeDirectoryForCurrentUser
            )
            search.onClose = { [weak self] in self?.advancedSearch = nil }
            search.onShowInFolder = { [weak self] url in
                guard let self else { return }
                if let window = self.activeWindow {
                    window.newTab(at: url)
                    window.window.present()
                } else {
                    self.openWindow(at: url)
                }
            }
            advancedSearch = search
        }
        if let criteria { SearchHandoffCenter.shared.hand(criteria) }
        advancedSearch?.present()
    }

    private var historyWindow: HistoryWindow?

    /// The History window (one): opened or brought forward.
    func openHistory() {
        if historyWindow == nil {
            let window = HistoryWindow(application: application)
            window.onClose = { [weak self] in self?.historyWindow = nil }
            window.onOpen = { [weak self] url in
                guard let self else { return }
                if let active = self.activeWindow {
                    _ = active.activePane?.navigate(to: url)
                    active.window.present()
                } else {
                    self.openWindow(at: url)
                }
            }
            historyWindow = window
        }
        historyWindow?.present()
    }

    private var quickLook: QuickLookWindow?

    /// Quick Look (one): opened for `pane`'s selection, or closed if it is
    /// already showing.
    func toggleQuickLook(for pane: FileListViewModel) {
        if let open = quickLook {
            open.window.close()
            return
        }
        let window = QuickLookWindow(application: application)
        window.onClose = { [weak self] in self?.quickLook = nil }
        quickLook = window
        window.present(for: pane)
    }

    /// The active tab or window changed: Quick Look follows the new pane.
    func quickLookFollows(_ pane: FileListViewModel) {
        quickLook?.bind(to: pane)
    }

    private var helpWindow: HelpWindow?

    /// The Help window (one): opened or brought forward, at `topic`.
    func openHelp(topic: HelpTopicID? = nil) {
        if helpWindow == nil {
            let window = HelpWindow(application: application)
            window.onClose = { [weak self] in self?.helpWindow = nil }
            helpWindow = window
        }
        helpWindow?.present(topic: topic)
    }

    private var duplicates: DuplicatesWindow?

    /// The Find Duplicates window (one): opened or brought forward, and
    /// scanning `roots`.
    func openDuplicates(roots: [URL]) {
        if duplicates == nil {
            let window = DuplicatesWindow(application: application)
            window.onClose = { [weak self] in self?.duplicates = nil }
            window.onShowInFolder = { [weak self] url in
                guard let self else { return }
                if let active = self.activeWindow {
                    active.newTab(at: url)
                    active.window.present()
                } else {
                    self.openWindow(at: url)
                }
            }
            duplicates = window
        }
        duplicates?.present()
        duplicates?.start(roots)
    }

    /// Foundation on Linux keeps `UserDefaults` in memory until `synchronize()`
    /// writes `~/.config/<program>.plist`, and nothing else calls it, so
    /// settings, the theme and the window layout would be lost at quit. Save
    /// every couple of seconds (it writes only when something changed), and
    /// when quitting.
    private func startSavingPreferences() {
        func save() {
            MainContext.delay(ms: 2000) { [weak self] in
                self?.saveSession()
                UserDefaults.standard.synchronize()
                save()
            }
        }
        save()
    }

    /// Back to front by when each was last in front is not tracked on GTK;
    /// the active window goes last so it reopens on top.
    private func saveSession() {
        let active = activeWindow
        sessionKeeper.save(windows.filter { $0 !== active } + (active.map { [$0] } ?? []))
    }

    func openSettings() {
        guard let themes = themeController?.store else { return }
        let dialog = SettingsDialog(themes: themes, sessions: sessionKeeper, parent: activeWindow)
        dialog.onChange = { [weak self] in self?.windows.forEach { $0.applySettingsChange() } }
        settings = dialog
        dialog.present()
    }

    @discardableResult
    func openWindow(at url: URL? = nil, restoring saved: SavedWindow? = nil, startingTab: Tab? = nil, awaitingTransfer: Bool = false) -> AppWindow? {
        let window = AppWindow(app: self, startingAt: url, restoring: saved, startingTab: startingTab, awaitingTransfer: awaitingTransfer)
        windows.append(window)
        window.window.onCloseRequest { [weak self, weak window] in
            guard let self else { return false }
            // Closing the last window quits, so ask first when a copy is running.
            if self.windows.count <= 1, self.hasRunningOperations {
                self.requestQuit()
                return true
            }
            if self.windows.count <= 1 { self.saveSession() }
            self.windows.removeAll { $0 === window }
            return false
        }
        return window
    }

    private var hasRunningOperations: Bool { !FileOperationProgressCenter.shared.operations.isEmpty }

    /// Quits, after asking when a copy, move, compress or extract is still
    /// running: quitting stops it partway through.
    func requestQuit() {
        let center = FileOperationProgressCenter.shared
        guard hasRunningOperations else {
            saveSession()
            UserDefaults.standard.synchronize()
            application.quit()
            return
        }
        let dialog = Dialogs.alert(
            heading: "A file operation is still running",
            body: "Quitting now will stop it partway through. Anything being copied, compressed or extracted may be incomplete.",
            responses: [("cancel", "Keep Working"), ("quit", "Quit")],
            destructive: "quit", defaultResponse: "cancel"
        )
        dialog.onResponse { [weak self] response in
            guard response == "quit" else { return }
            for operation in center.operations { center.requestCancel(operation.id) }
            self?.saveSession()
            UserDefaults.standard.synchronize()
            self?.application.quit()
        }
        dialog.present(activeWindow?.window)
    }

    private func showAbout() {
        let dialog = AboutDialog()
        dialog.applicationName = "OneRoot"
        dialog.applicationIcon = OneRootApp.id
        dialog.version = AppVersion.current
        dialog.developerName = "Eric Hebert"
        dialog.website = "https://oneroot.hillcraft-sc.com"
        dialog.copyright = "Copyright © 2026 Eric Hebert"
        dialog.licenseType = GTK_LICENSE_CUSTOM
        dialog.license = "OneRoot is free software under the GNU General Public License, version 3 (GPL-3.0-only). See https://www.gnu.org/licenses/gpl-3.0.html. The OneRoot name and icon are not covered by this license; see TRADEMARKS.md."
        dialog.present(windows.last?.window)
    }
}

enum AppVersion {
    static let current = "0.2.0"
}

/// ONEROOT_TRACE=1: notes to standard error, for debugging.
func trace(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["ONEROOT_TRACE"] == "1" else { return }
    FileHandle.standardError.write(Data("[OneRoot] \(message())\n".utf8))
}
