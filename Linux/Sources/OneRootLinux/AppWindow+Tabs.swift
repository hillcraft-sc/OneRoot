import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Tab commands beyond New/Close: the tab strip's right-click menu and the
/// matching window actions (the Mac's File and View menu items).
extension AppWindow {
    /// The tab a command applies to: the one right-clicked, else the active one.
    private var commandTab: Tab? { menuTab ?? viewModel.activeTab }

    func addTabActions(_ action: (_ name: String, _ accels: [String], _ handler: @escaping @MainActor () -> Void) -> Void) {
        action("duplicate-tab", []) { [weak self] in
            guard let self else { return }
            if let tab = self.menuTab, tab.id != self.viewModel.activeTabID { self.viewModel.selectTab(tab) }
            self.viewModel.duplicateActiveTab()
            self.menuTab = nil
        }
        action("close-other-tabs", []) { [weak self] in
            guard let self, let tab = self.commandTab else { return }
            self.menuTab = nil
            self.viewModel.closeOtherTabs(keeping: tab)
        }
        action("close-tabs-right", []) { [weak self] in
            guard let self, let tab = self.commandTab else { return }
            self.menuTab = nil
            self.viewModel.closeTabsToTheRight(of: tab)
        }
        action("close-tab-menu", []) { [weak self] in
            guard let self, let tab = self.commandTab else { return }
            self.menuTab = nil
            self.requestCloseTab(tab)
        }
        action("next-tab", ["<Control>Tab", "<Control>Page_Down"]) { [weak self] in
            self?.viewModel.selectAdjacentTab(1)
        }
        action("previous-tab", ["<Control><Shift>Tab", "<Control>Page_Up"]) { [weak self] in
            self?.viewModel.selectAdjacentTab(-1)
        }
        action("move-tab-to-new-window", []) { [weak self] in
            guard let self else { return }
            if let tab = self.menuTab, tab.id != self.viewModel.activeTabID { self.viewModel.selectTab(tab) }
            self.menuTab = nil
            guard let tab = self.viewModel.detachActiveTabForNewWindow() else {
                self.showToast("Only one tab: nothing to move")
                return
            }
            self.app.openWindow(startingTab: tab)
        }
        installTabMenu()
    }

    /// Records which tab the context menu opened on. Raw GObject connection:
    /// AdwTabView also emits `setup-menu` with a NULL page when the menu
    /// closes, which the binding's typed handler can't take. The actions run
    /// after that, so a NULL page is ignored and each action clears the
    /// recorded tab itself.
    func connectTabMenuSetup() {
        let box = Unmanaged.passRetained(WeakWindow(self))
        let callback: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, page, data in
            guard let page, let data else { return }
            let owner = Unmanaged<WeakWindow>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard let window = owner.window else { return }
                window.menuTab = window.tab(for: TabPage(borrowing: UnsafeMutableRawPointer(page)))
            }
        }
        let release: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
            if let data { Unmanaged<WeakWindow>.fromOpaque(data).release() }
        }
        g_signal_connect_data(UnsafeMutableRawPointer(tabView.opaquePointer), "setup-menu",
                              unsafeBitCast(callback, to: GCallback.self), box.toOpaque(),
                              unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
    }

    private final class WeakWindow {
        weak var window: AppWindow?
        init(_ window: AppWindow) { self.window = window }
    }

    private func installTabMenu() {
        let menu = GMenuRef()
        let tabs = GMenuRef()
        tabs.append("New Tab", action: "win.new-tab")
        tabs.append("Duplicate Tab", action: "win.duplicate-tab")
        tabs.append("Move Tab to New Window", action: "win.move-tab-to-new-window")
        menu.appendSection(nil, section: tabs)
        let close = GMenuRef()
        close.append("Close Tab", action: "win.close-tab-menu")
        close.append("Close Other Tabs", action: "win.close-other-tabs")
        close.append("Close Tabs to the Right", action: "win.close-tabs-right")
        menu.appendSection(nil, section: close)
        adw_tab_view_set_menu_model(tabView.opaquePointer, menu.menuModelPointer)
    }
}

extension AppWindow {
    /// Right-click (or long-press) on Back/Forward lists the folders it
    /// would reach; choosing one goes there.
    func addHistoryMenu(to button: Button, label: String, forward: Bool, history: @escaping (FileListViewModel) -> [URL]) {
        let show: @MainActor () -> Void = { [weak self, weak button] in
            guard let self, let button, let model = self.activePane else { return }
            let urls = Array(history(model).prefix(30))
            guard !urls.isEmpty else { return }
            let items = urls.enumerated().map { index, url in
                LocationListPopover.Item(Self.historyTitle(url), icon: "folder-symbolic") { [weak self] in
                    // Step through history (the list is nearest first).
                    if forward { self?.activePane?.goForward(steps: index + 1) } else { self?.activePane?.goBack(steps: index + 1) }
                }
            }
            LocationListPopover.show(items, from: button, label: label)
        }
        let rightClick = GestureClick()
        rightClick.button = 3
        rightClick.onPressed { _, _, _ in show() }
        button.addController(rightClick)
        let longPress = GestureLongPress()
        longPress.onPressed { _, _ in show() }
        button.addController(longPress)
    }

    private static func historyTitle(_ url: URL) -> String {
        if let location = VirtualLocation(url: url) { return location.title }
        return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }
}

extension AppWindow {
    /// Go ▸ Recent Locations: the last dozen folders visited anywhere in
    /// the app (the shared history), as a list under the path bar, with
    /// Show All History and Clear.
    func showRecentLocations() {
        let history = NavigationHistoryStore.shared
        var items: [LocationListPopover.Item] = history.entries.prefix(12).map { url in
            let name = url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? url.path : url.lastPathComponent
            return LocationListPopover.Item(name, icon: "folder-symbolic") { [weak self] in
                _ = self?.activePane?.navigate(to: url)
            }
        }
        if items.isEmpty { items.append(LocationListPopover.Item("No Recent Locations") {}) }
        items.append(LocationListPopover.Item("Show All History\u{2026}", icon: "document-open-recent-symbolic") { [weak self] in
            self?.app.openHistory()
        })
        if !history.entries.isEmpty {
            items.append(LocationListPopover.Item("Clear Menu", icon: "edit-clear-all-symbolic") { history.clear() })
        }
        LocationListPopover.show(items, from: pathBar.widget, label: "Recent Locations")
    }
}

extension AppWindow {
    /// The All Tabs list: every tab's title, the current one first marked
    /// with a check; choosing one switches to it.
    func showAllTabs(from anchor: Widget) {
        var items: [LocationListPopover.Item] = []
        for index in 0..<tabView.nPages {
            let page = tabView.getNthPage(index)
            let isCurrent = tabView.selectedPage?.isSame(as: page) ?? false
            items.append(LocationListPopover.Item((isCurrent ? "\u{2713} " : "") + page.title, icon: "folder-symbolic") { [weak self] in
                self?.tabView.selectedPage = page
            })
        }
        LocationListPopover.show(items, from: anchor, label: "All Tabs")
    }
}
