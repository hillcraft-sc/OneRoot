import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// One OneRoot window: tabs, the destinations sidebar, the file list(s),
/// the path bar and the status line, over the shared `WindowViewModel` —
/// the GTK counterpart of the Mac's MainWindowView.
@MainActor
final class AppWindow {
    let window: ApplicationWindow
    let viewModel: WindowViewModel
    let destinations: DestinationsViewModel
    let app: OneRootApp

    let tabView = TabView()
    private let tabBar = TabBar()
    let pathBar = PathBar()
    let sidebar: Sidebar
    private let backButton = Button(iconName: "go-previous-symbolic")
    private let forwardButton = Button(iconName: "go-next-symbolic")
    private let upButton = Button(iconName: "go-up-symbolic")
    private let statusLabel = Label("")
    private let spaceLabel = Label("")
    let outerPaned = Paned(orientation: GTK_ORIENTATION_HORIZONTAL)
    let hierarchyPaned = Paned(orientation: GTK_ORIENTATION_HORIZONTAL)
    let inspectorPaned = Paned(orientation: GTK_ORIENTATION_HORIZONTAL)
    let hierarchyModel: FolderHierarchyViewModel
    private var hierarchyCoordinator: HierarchyCoordinator?
    let hierarchyPane: HierarchyPane
    let inspector = InspectorPane()
    let hierarchyButton = ToggleButton()
    let inspectorButton = ToggleButton()
    let dualPaneButton = ToggleButton()
    let contextBar: ContextBar
    var dualPaneWatch: ObservationWatch?
    var sidebarToggle: ToggleButton?
    var layoutWatch: ObservationWatch?
    var isApplyingLayout = false
    var lastAppliedLayout: WindowLayout?
    private let toastOverlay = ToastOverlay()
    let operationsPanel = OperationsPanel()
    let visualizePanel = VisualizePanel()
    private let operationsButton = Button(label: "File Operations")
    private var operationsWatches: [ObservationWatch] = []

    var contents: [Tab.ID: TabContent] = [:]
    var fileActions: [String: SimpleAction] = [:]
    var promptWatches: [ObjectIdentifier: [ObservationWatch]] = [:]
    private var pages: [Tab.ID: TabPage] = [:]
    private var closingPages: Set<UnsafeMutableRawPointer> = []
    private var isSyncingTabs = false
    /// The tab the tab-strip context menu was opened on.
    var menuTab: Tab?
    private var watches: [ObservationWatch] = []
    private var tabWatch: ObservationWatch?
    private var paneWatches: [ObservationWatch] = []
    /// The sidebar row a context menu is open for.
    var sidebarMenuEntry: Sidebar.Entry?
    private var tabTitleWatches: [Tab.ID: ObservationWatch] = [:]
    private weak var focusedPane: FileListViewModel?
    private var spaceTask: Task<Void, Never>?
    private var destinationErrorWatch: ObservationWatch?

    /// `saved` reopens a window from the last session (its tabs, splits,
    /// sort orders, layout and size); otherwise one tab opens at `url`.
    init(app: OneRootApp, startingAt url: URL? = nil, restoring saved: SavedWindow? = nil, startingTab: Tab? = nil, awaitingTransfer: Bool = false) {
        self.app = app
        window = ApplicationWindow(application: app.application)
        window.title = "OneRoot"
        window.defaultWidth = saved?.frame.map { Int($0.width) } ?? 1400
        window.defaultHeight = saved?.frame.map { Int($0.height) } ?? 740

        let layoutService = WindowLayoutService()
        if let saved {
            viewModel = WindowViewModel(
                fileWatcherFactory: { Platform.makeFileWatcher() },
                layoutService: layoutService,
                restoring: saved
            )
        } else {
            viewModel = WindowViewModel(
                fileWatcherFactory: { Platform.makeFileWatcher() },
                layout: WindowLayoutModel(layout: layoutService.load(), service: layoutService),
                startingTab: startingTab,
                opensDefaultTab: false
            )
        }
        destinations = DestinationsViewModel(
            trashURL: Platform.trashFolder,
            userFolders: Platform.userFolders(home: FileManager.default.homeDirectoryForCurrentUser)
        )
        sidebar = Sidebar(destinations: destinations)
        contextBar = ContextBar(dualPaneButton: dualPaneButton)
        hierarchyModel = FolderHierarchyViewModel(fileWatcher: Platform.makeFileWatcher())
        hierarchyPane = HierarchyPane(model: hierarchyModel, showsHidden: { [weak viewModel] in
            viewModel?.activeTab?.fileListViewModel.showHiddenFiles ?? false
        })

        buildLayout()
        contextBar.onViewMode = { [weak self] mode in self?.activePane?.setViewMode(mode) }
        contextBar.isInTrash = { [weak self] in self?.isTrashShown ?? false }
        contextBar.quickOptions = { [weak self] in
            guard let self, let pane = self.activePane else { return [] }
            return pane.quickActionOptions(for: pane.selectedNodes)
        }
        addActions()
        addFileActions()
        wireSidebar()
        wireTabs()
        wirePanes()
        hierarchyCoordinator = HierarchyCoordinator(windowViewModel: viewModel, destinations: destinations, hierarchy: hierarchyModel)
        wireLayout()

        pathBar.onNavigate = { [weak self] url in
            self?.viewModel.activeTab?.fileListViewModel.navigate(to: url)
        }
        pathBar.onOpenInNewTab = { [weak self] url in self?.newTab(at: url) }
        pathBar.onCopyPath = { [weak self] url in
            self?.activePane?.copyPaths([url])
            self?.showToast("Copied the path")
        }
        pathBar.onDrop = { [weak self] urls, folder, move in
            self?.activePane?.handleDrop(urls: urls, into: folder, move: move)
        }
        pathBar.volumeRoots = { [weak self] in
            self?.destinations.allDestinations
                .filter { $0.kind == .volume || $0.kind == .networkVolume }
                .map { ($0.url, $0.name) } ?? []
        }

        if saved == nil, startingTab == nil, !awaitingTransfer {
            viewModel.openNewTab(at: url ?? FileManager.default.homeDirectoryForCurrentUser)
        }
        window.present()
    }

    // MARK: Layout

    private func buildLayout() {
        let header = HeaderBar()
        let sidebarButton = ToggleButton()
        sidebarButton.child = Image(iconName: "sidebar-show-symbolic")
        sidebarButton.tooltipText = "Sidebar (F9)"
        sidebarButton.active = true
        sidebarButton.onToggled { [weak self, weak sidebarButton] in
            guard let self, let sidebarButton, !self.isApplyingLayout else { return }
            self.viewModel.layout.set(\.showsDestinations, sidebarButton.active)
        }
        sidebarButton.setAccessibleLabel("Show sidebar")
        sidebarToggle = sidebarButton
        header.packStart(sidebarButton)

        hierarchyButton.child = Image(iconName: "view-list-bullet-symbolic")
        hierarchyButton.tooltipText = "Folder Hierarchy (Shift+F9)"
        hierarchyButton.setAccessibleLabel("Show folder hierarchy")
        hierarchyButton.onToggled { [weak self] in
            guard let self, !self.isApplyingLayout else { return }
            self.viewModel.layout.set(\.showsHierarchy, self.hierarchyButton.active)
        }
        header.packStart(hierarchyButton)

        let nav = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        nav.addCSSClass(.linked)
        backButton.tooltipText = "Back (Alt+Left)"
        backButton.setAccessibleLabel("Back")
        forwardButton.setAccessibleLabel("Forward")
        upButton.setAccessibleLabel("Enclosing folder")
        forwardButton.tooltipText = "Forward (Alt+Right)"
        upButton.tooltipText = "Enclosing Folder (Alt+Up)"
        backButton.onClicked { [weak self] in self?.activePane?.goBack() }
        forwardButton.onClicked { [weak self] in self?.activePane?.goForward() }
        upButton.onClicked { [weak self] in self?.activePane?.goUp() }
        addHistoryMenu(to: backButton, label: "Back history", forward: false) { $0.backHistory }
        addHistoryMenu(to: forwardButton, label: "Forward history", forward: true) { $0.forwardHistory }
        nav.append(backButton)
        nav.append(forwardButton)
        header.packStart(nav)
        header.packStart(upButton)
        let refresh = Button(iconName: "view-refresh-symbolic")
        refresh.tooltipText = "Reload (Ctrl+R)"
        refresh.setAccessibleLabel("Reload")
        refresh.onClicked { [weak self] in _ = self?.viewModel.activeTab?.refresh() }
        header.packStart(refresh)

        header.titleWidget = pathBar.widget
        header.packEnd(makeMainMenuButton())
        inspectorButton.child = Image(iconName: "sidebar-show-right-symbolic")
        inspectorButton.tooltipText = "Inspector (Ctrl+I)"
        inspectorButton.setAccessibleLabel("Show inspector")
        inspectorButton.onToggled { [weak self] in
            guard let self, !self.isApplyingLayout else { return }
            self.viewModel.layout.set(\.showsInspector, self.inspectorButton.active)
        }
        header.packEnd(inspectorButton)
        dualPaneButton.child = Image(iconName: "view-dual-symbolic")
        dualPaneButton.tooltipText = "Dual Pane (Ctrl+\\)"
        dualPaneButton.setAccessibleLabel("Dual Pane")
        dualPaneButton.onToggled { [weak self] in
            guard let self, let tab = self.viewModel.activeTab, tab.isSplit != self.dualPaneButton.active else { return }
            self.viewModel.toggleSplitActiveTab()
        }

        tabBar.view = tabView
        tabBar.autohide = false
        let newTab = Button(iconName: "tab-new-symbolic")
        newTab.tooltipText = "New Tab (Ctrl+T)"
        newTab.setAccessibleLabel("New tab")
        newTab.addCSSClass(.flat)
        newTab.onClicked { [weak self] in self?.newTab() }
        tabBar.endActionWidget = newTab
        // Too many tabs to fit: the strip scrolls, and this lists them all
        // (the Mac's "N more tabs" menu).
        let allTabs = Button(iconName: "view-list-symbolic")
        allTabs.tooltipText = "All Tabs"
        allTabs.setAccessibleLabel("All tabs")
        allTabs.addCSSClass(.flat)
        allTabs.opacity = 0
        allTabs.sensitive = false
        allTabs.onClicked { [weak self, weak allTabs] in
            guard let self, let allTabs else { return }
            self.showAllTabs(from: allTabs)
        }
        tabBar.startActionWidget = allTabs
        tabBar.onNotify(.custom("is-overflowing")) { [weak self, weak allTabs] in
            guard let self else { return }
            allTabs?.opacity = self.tabBar.isOverflowing ? 1 : 0
            allTabs?.sensitive = self.tabBar.isOverflowing
        }

        let status = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        status.addCSSClass("oneroot-status")
        statusLabel.xalign = 0
        statusLabel.hexpand = true
        statusLabel.ellipsize = PANGO_ELLIPSIZE_END
        spaceLabel.xalign = 1
        for label in [statusLabel, spaceLabel] {
            label.addCSSClass(.dimLabel)
            label.addCSSClass("caption")
            status.append(label)
        }

        operationsButton.addCSSClass(.flat)
        operationsButton.addCSSClass("caption")
        operationsButton.tooltipText = "File Operations (Ctrl+Shift+O)"
        operationsButton.setAccessibleLabel("File Operations")
        operationsButton.onClicked { [weak self] in self?.operationsPanel.toggle() }
        status.append(operationsButton)
        visualizePanel.onOpenFolder = { [weak self] url in _ = self?.activePane?.navigate(to: url) }
        visualizePanel.onReveal = { [weak self] url in self?.activePane?.reveal(url) }
        let center = FileOperationProgressCenter.shared
        operationsWatches.append(ObservationWatch.watch({ (center.operations.count, center.unseenFailureCount) }) { [weak self] counts in
            self?.updateOperationsButton(running: counts.0, failed: counts.1)
        })

        sidebar.widget.setSizeRequest(width: 160)
        // Destinations | hierarchy | tabs | inspector, each collapsible.
        tabView.setSizeRequest(width: 360)
        inspectorPaned.startChild = tabView
        inspectorPaned.endChild = inspector.widget
        inspectorPaned.resizeStartChild = true
        inspectorPaned.resizeEndChild = false
        inspectorPaned.shrinkEndChild = true
        inspectorPaned.shrinkStartChild = true
        hierarchyPaned.startChild = hierarchyPane.widget
        hierarchyPaned.endChild = inspectorPaned
        hierarchyPaned.resizeStartChild = false
        hierarchyPaned.shrinkStartChild = true
        hierarchyPaned.shrinkEndChild = false
        outerPaned.startChild = sidebar.widget
        outerPaned.endChild = hierarchyPaned
        outerPaned.shrinkStartChild = true
        outerPaned.shrinkEndChild = false
        outerPaned.resizeStartChild = false

        let toolbar = ToolbarView()
        toolbar.addTopBar(header)
        toolbar.addTopBar(tabBar)
        toolbar.addTopBar(contextBar.widget)
        toolbar.setContent(outerPaned)
        toolbar.addBottomBar(visualizePanel.widget)
        toolbar.addBottomBar(operationsPanel.widget)
        toolbar.addBottomBar(status)
        toastOverlay.child = toolbar
        window.setContent(toastOverlay)
    }

    private func updateOperationsButton(running: Int, failed: Int) {
        var label = "File Operations"
        if running > 0 { label += running == 1 ? " \u{00B7} 1 running" : " \u{00B7} \(running) running" }
        if failed > 0 { label += failed == 1 ? " \u{00B7} 1 failed" : " \u{00B7} \(failed) failed" }
        operationsButton.label = label
    }

    private func makeMainMenuButton() -> MenuButton {
        let menu = GMenuRef()
        let windows = GMenuRef()
        windows.append("New Window", action: "app.new-window")
        windows.append("New Tab", action: "win.new-tab")
        windows.append("New Workspace\u{2026}", action: "win.new-workspace")
        menu.appendSection(nil, section: windows)
        let view = GMenuRef()
        view.append("Filter This Folder", action: "win.find")
        view.append("Advanced Search\u{2026}", action: "win.advanced-search")
        view.append("Find Duplicates\u{2026}", action: "win.find-duplicates")
        view.append("Show Hidden Files", action: "win.show-hidden")
        view.append("Show All Files in Subfolders", action: "win.show-all-files")
        view.append("Collapse All Folders", action: "win.collapse-folders")
        view.append("Expand Top Level", action: "win.expand-top-level")
        view.append("Tools Panel", action: "win.tools-panel")
        view.append("Reset Window Layout", action: "win.reset-layout")
        view.append("Reload", action: "win.reload")
        let network = GMenuRef()
        network.append("Connect to Server\u{2026}", action: "win.connect-to-server")
        network.append("Browse Network\u{2026}", action: "win.browse-network")
        network.append("Copy via SSH\u{2026}", action: "win.copy-via-ssh")
        network.append("Eject / Disconnect", action: "win.eject")
        let recents = GMenuRef()
        recents.append("Recent Locations\u{2026}", action: "win.recent-locations")
        recents.append("Show All History\u{2026}", action: "win.show-history")
        menu.appendSection(nil, section: recents)
        menu.appendSection(nil, section: network)
        let panes = GMenuRef()
        panes.append("Dual Pane", action: "win.toggle-dual-pane")
        panes.append("Compare Panes", action: "win.compare-panes")
        panes.append("Swap Panes", action: "win.swap-panes")
        panes.append("Switch Pane", action: "win.switch-pane")
        menu.appendSection(nil, section: panes)
        view.append("Visualize Storage", action: "win.visualize")
        view.append("File Operations", action: "win.file-operations")
        menu.appendSection(nil, section: view)
        let about = GMenuRef()
        about.append("Settings", action: "app.settings")
        about.append("Keyboard Shortcuts", action: "app.shortcuts")
        about.append("Help", action: "app.help")
        about.append("About OneRoot", action: "app.about")
        menu.appendSection(nil, section: about)
        let button = MenuButton()
        button.iconName = "open-menu-symbolic"
        button.tooltipText = "Main Menu"
        button.setAccessibleLabel("Main menu")
        button.setMenuModel(menu)
        button.primary = true
        return button
    }

    // MARK: Tabs

    private func wireTabs() {
        watches.append(ObservationWatch.watch({ [viewModel] in viewModel.tabs.map(\.id) }) { [weak self] _ in
            self?.syncTabs()
        })
        watches.append(ObservationWatch.watch({ [viewModel] in viewModel.activeTabID }) { [weak self] _ in
            self?.syncSelectedTab()
        })
        tabView.onNotify(.custom("selected-page")) { [weak self] in
            guard let self, !self.isSyncingTabs, let page = self.tabView.selectedPage,
                  let tab = self.tab(for: page) else { return }
            self.viewModel.selectTab(tab)
        }
        tabView.onClosePage { [weak self] page in
            guard let self else { return false }
            if self.closingPages.remove(page.pointer) != nil {
                self.tabView.closePageFinish(page, confirm: true)
            } else {
                self.tabView.closePageFinish(page, confirm: false)
                if let tab = self.tab(for: page) { self.requestCloseTab(tab) }
            }
            return true
        }
        connectTabMenuSetup()
        connectTabTransfer()
        tabView.onPageReordered { [weak self] page, position in
            guard let self, !self.isSyncingTabs, let tab = self.tab(for: page) else { return }
            self.viewModel.moveTab(tab, to: position)
        }
    }

    // MARK: Tabs dragged between windows

    /// Tabs mid-drag between windows, keyed by their page's child widget:
    /// set by the window they leave, taken by the window they land in.
    private static var transferring: [UnsafeMutableRawPointer: Tab] = [:]

    /// AdwTabView moves a dragged page to another window's strip by itself;
    /// the model must follow. The source releases the Tab on `page-detached`,
    /// the destination adopts it on `page-attached` and rebuilds its page
    /// (the moved one is closed). The Tab keeps its folder, history and sort.
    private func connectTabTransfer() {
        let box = Unmanaged.passRetained(TransferOwner(self))
        let release: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
            if let data { Unmanaged<TransferOwner>.fromOpaque(data).release() }
        }
        let detached: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { _, page, _, data in
            guard let page, let data else { return }
            let owner = Unmanaged<TransferOwner>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { owner.window?.pageDetached(TabPage(borrowing: UnsafeMutableRawPointer(page))) }
        }
        let attached: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { _, page, position, data in
            guard let page, let data else { return }
            let owner = Unmanaged<TransferOwner>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { owner.window?.pageAttached(TabPage(borrowing: UnsafeMutableRawPointer(page)), at: Int(position)) }
        }
        // A tab dragged out of every strip: hand AdwTabView an empty new
        // window's tab view; it moves the page there (page-attached adopts it).
        let createWindow: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> OpaquePointer? = { _, data in
            guard let data else { return nil }
            let owner = Unmanaged<TransferOwner>.fromOpaque(data).takeUnretainedValue()
            return MainActor.assumeIsolated { owner.window?.app.openWindow(awaitingTransfer: true)?.tabView.opaquePointer }
        }
        let box3 = Unmanaged.passRetained(TransferOwner(self))
        g_signal_connect_data(UnsafeMutableRawPointer(tabView.opaquePointer), "create-window",
                              unsafeBitCast(createWindow, to: GCallback.self), box3.toOpaque(),
                              unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        g_signal_connect_data(UnsafeMutableRawPointer(tabView.opaquePointer), "page-detached",
                              unsafeBitCast(detached, to: GCallback.self), box.toOpaque(),
                              unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        let box2 = Unmanaged.passRetained(TransferOwner(self))
        g_signal_connect_data(UnsafeMutableRawPointer(tabView.opaquePointer), "page-attached",
                              unsafeBitCast(attached, to: GCallback.self), box2.toOpaque(),
                              unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
    }

    private final class TransferOwner {
        weak var window: AppWindow?
        init(_ window: AppWindow) { self.window = window }
    }

    private func pageDetached(_ page: TabPage) {
        // Our own closes are not transfers.
        guard !closingPages.contains(page.pointer), let tab = tab(for: page) else { return }
        Self.transferring[page.child.widgetPointer] = tab
        if let id = pages.first(where: { $0.value.isSame(as: page) })?.key {
            pages[id] = nil
            for pane in contents[id]?.panes ?? [] { promptWatches[ObjectIdentifier(pane.viewModel)] = nil }
            contents[id] = nil
            tabTitleWatches[id] = nil
        }
        viewModel.detachTab(tab)  // an emptied window closes, as dragging out the last tab does
    }

    private func pageAttached(_ page: TabPage, at position: Int) {
        guard !isSyncingTabs, let tab = Self.transferring.removeValue(forKey: page.child.widgetPointer) else { return }
        viewModel.insertTab(tab, at: position)  // syncTabs builds this window's own page
        closingPages.insert(page.pointer)
        MainContext.delay(ms: 0) { [weak self] in self?.tabView.closePage(page) }
    }

    /// Closes `tab`, asking first when it is the last one (it closes the
    /// window) and Settings ▸ Warn before closing the last tab is on.
    func requestCloseTab(_ tab: Tab) {
        guard viewModel.tabs.count == 1, CloseLastTabPreferenceService().shouldWarn else {
            viewModel.closeTab(tab)
            return
        }
        let dialog = Dialogs.alert(
            heading: "Close the last tab?",
            body: "Closing it closes the window.",
            responses: [("cancel", "Cancel"), ("close", "Close")],
            destructive: "close", defaultResponse: "cancel"
        )
        dialog.onResponse { [weak self] response in
            if response == "close" { self?.viewModel.closeTab(tab) }
        }
        dialog.present(window)
    }

    func tab(for page: TabPage) -> Tab? {
        guard let id = pages.first(where: { $0.value.isSame(as: page) })?.key else { return nil }
        return viewModel.tabs.first { $0.id == id }
    }

    private func syncTabs() {
        isSyncingTabs = true
        defer { isSyncingTabs = false }
        let ids = Set(viewModel.tabs.map(\.id))
        for (id, page) in pages where !ids.contains(id) {
            closingPages.insert(page.pointer)
            tabView.closePage(page)
            pages[id] = nil
            for pane in contents[id]?.panes ?? [] { promptWatches[ObjectIdentifier(pane.viewModel)] = nil }
            contents[id] = nil
            tabTitleWatches[id] = nil
        }
        for (index, tab) in viewModel.tabs.enumerated() {
            if let page = pages[tab.id] {
                if tabView.getPagePosition(page) != index { _ = tabView.reorderPage(page, position: index) }
                continue
            }
            let content = TabContent(tab: tab) { [weak self] model in
                self?.makePane(for: model, in: tab) ?? FileListPane(viewModel: model)
            }
            content.dialogParent = { [weak self] in self?.window }
            content.onPopOut = { [weak self] side in
                guard let self, let model = tab.detach(side) else { return }
                self.app.openWindow(startingTab: Tab(fileListViewModel: model))
            }
            contents[tab.id] = content
            let page = tabView.insert(content.widget, position: index)
            pages[tab.id] = page
            tabTitleWatches[tab.id] = ObservationWatch.watch({ tab.fileListViewModel.currentLocationURL }) { [weak page] url in
                guard let page else { return }
                page.title = Self.title(for: url)
                page.tooltip = url?.path
            }
        }
        if viewModel.tabs.isEmpty {
            window.close()
        }
        syncSelectedTab()
    }

    private func syncSelectedTab() {
        guard let id = viewModel.activeTabID, let page = pages[id] else { return }
        if !(tabView.selectedPage?.isSame(as: page) ?? false) {
            isSyncingTabs = true
            gtk_widget_grab_focus(page.child.widgetPointer)
            adw_tab_view_set_selected_page(tabView.opaquePointer, page.opaquePointer)
            isSyncingTabs = false
        }
        bindActiveTab()
    }

    static func title(for url: URL?) -> String {
        guard let url else { return "OneRoot" }
        if let location = VirtualLocation(url: url) { return location.title }
        if url.path == FileManager.default.homeDirectoryForCurrentUser.path { return "Home" }
        if url.path == "/" { return "Computer" }
        if url.path == Platform.trashFolder.path { return "Trash" }
        return url.lastPathComponent
    }

    func newTab(at url: URL? = nil) {
        let location = url ?? activePane?.currentLocationURL ?? FileManager.default.homeDirectoryForCurrentUser
        viewModel.openNewTab(at: location, root: viewModel.activeTab?.hierarchyRoot)
    }

    // MARK: The active pane

    var activePane: FileListViewModel? { viewModel.activeTab?.fileListViewModel }

    var activeContent: TabContent? {
        viewModel.activeTabID.flatMap { contents[$0] }
    }

    /// The path bar, buttons and status line follow the active tab's
    /// focused pane.
    private func bindActiveTab() {
        tabWatch = nil
        dualPaneWatch = nil
        guard let tab = viewModel.activeTab else { return }
        dualPaneWatch = ObservationWatch.watch({ tab.isSplit }) { [weak self] split in
            guard let self, self.dualPaneButton.active != split else { return }
            self.dualPaneButton.active = split
            self.contextBar.compareButton.visible = split
        }
        tabWatch = ObservationWatch.watch({ ObjectIdentifier(tab.fileListViewModel) }) { [weak self] _ in
            self?.bindFocusedPane()
        }
    }

    private func bindFocusedPane() {
        guard let tab = viewModel.activeTab else { return }
        let pane = tab.fileListViewModel
        let changed = pane !== focusedPane
        focusedPane = pane
        paneWatches = []
        paneWatches.append(ObservationWatch.watch({ pane.currentLocationURL }) { [weak self] url in
            guard let self else { return }
            self.pathBar.show(url, paneChanged: changed)
            self.window.title = "\(Self.title(for: url)) — OneRoot"
            self.sidebar.highlight(url.flatMap { VirtualLocation(url: $0) } != nil ? url : (tab.hierarchyRoot?.url ?? url))
            self.updateSpace(for: url)
            self.visualizePanel.setFolder(pane.currentDirectory)
        })
        paneWatches.append(ObservationWatch.watch({ (pane.canGoBack, pane.canGoForward, pane.canGoUp) }) { [weak self] state in
            self?.backButton.sensitive = state.0
            self?.forwardButton.sensitive = state.1
            self?.upButton.sensitive = state.2
        })
        paneWatches.append(ObservationWatch.watch({ (pane.items.count, pane.items.filter(\.isDirectory).count, pane.selectedNodes.count, pane.archiveOperationStatus, pane.isLoading) }) { [weak self] state in
            guard let self else { return }
            if let status = state.3 {
                self.statusLabel.text = status
            } else if state.4 && state.0 == 0 {
                self.statusLabel.text = "Loading…"
            } else {
                self.statusLabel.text = Formatting.summary(items: state.0, folders: state.1, selected: state.2)
            }
        })
        updateFileActions()
        contextBar.bind(to: pane)
        if window.isActive { app.quickLookFollows(pane) }
        if viewModel.layout.layout.showsInspector { inspector.bind(to: pane) }
        paneWatches.append(ObservationWatch.watch({ pane.errorMessage }) { [weak self] message in
            guard let self, let message else { return }
            self.showToast(message)
            pane.dismissError()
        })
    }

    private func updateSpace(for url: URL?) {
        spaceTask?.cancel()
        guard let url, VirtualLocation(url: url) == nil else {
            spaceLabel.text = ""
            return
        }
        let path = url.path
        spaceTask = Task { [weak self] in
            let space = await Task.detached { () -> (Int64, Int64)? in
                var info = statvfs()
                guard statvfs(path, &info) == 0 else { return nil }
                let block = Int64(info.f_frsize)
                return (Int64(info.f_bavail) * block, Int64(info.f_blocks) * block)
            }.value
            guard let self, !Task.isCancelled else { return }
            if let (available, total) = space, total > 0 {
                self.spaceLabel.text = "\(Formatting.size(available)) available of \(Formatting.size(total))"
            } else {
                self.spaceLabel.text = ""
            }
        }
    }

    // MARK: Panes

    private func makePane(for model: FileListViewModel, in tab: Tab) -> FileListPane {
        let pane = FileListPane(viewModel: model)
        pane.onOpenFile = { [weak self] node in self?.open(node.url) }
        pane.onFocus = { [weak tab, weak model] in
            guard let tab, let model else { return }
            let side: Pane = tab.primary === model ? .primary : .secondary
            if tab.focusedPane != side { tab.focus(side) }
        }
        pane.onContextMenu = { [weak self, weak pane] x, y in
            guard let self, let pane else { return }
            self.showContextMenu(in: pane, x: x, y: y)
        }
        pane.onSearchSubfolders = { [weak self] criteria in self?.app.openAdvancedSearch(handing: criteria) }
        pane.onKey = { [weak self] keyval, modifiers in
            self?.handleListKey(keyval, modifiers) ?? false
        }
        promptWatches[ObjectIdentifier(model)] = watchPrompts(of: model)
        return pane
    }

    /// The list's own keys, as in Nautilus and Dolphin.
    private func handleListKey(_ keyval: UInt32, _ modifiers: GdkModifierType) -> Bool {
        let shift = modifiers.rawValue & GDK_SHIFT_MASK.rawValue != 0
        let control = modifiers.rawValue & GDK_CONTROL_MASK.rawValue != 0
        let alt = modifiers.rawValue & GDK_ALT_MASK.rawValue != 0
        func run(_ name: String) -> Bool {
            fileActions[name]?.activate()
            return true
        }
        switch keyval {
        case UInt32(GDK_KEY_Delete), UInt32(GDK_KEY_KP_Delete):
            if shift { return run("delete-permanently") }
            return run(isTrashShown ? "delete-permanently" : "trash")
        case UInt32(GDK_KEY_F2):
            return run("rename")
        case UInt32(GDK_KEY_slash) where !control && !alt:
            return run("find")
        case UInt32(GDK_KEY_BackSpace):
            activePane?.goBack()
            return true
        case UInt32(GDK_KEY_Return), UInt32(GDK_KEY_KP_Enter):
            if alt { return false }
            if control { return run("open-new-tab") }
            return run("open")
        case UInt32(GDK_KEY_space) where !control && !alt && !shift:
            guard let pane = focusedListPane, !pane.viewModel.selectedNodes.isEmpty else { return false }
            return run("quick-look")
        case UInt32(GDK_KEY_Escape):
            guard let pane = focusedListPane, !(pane.viewModel.selectedNodes.isEmpty) else { return false }
            pane.deselectAll()
            return true
        default:
            guard !control, !alt, let pane = focusedListPane else { return false }
            let scalar = gdk_keyval_to_unicode(keyval)
            guard scalar > 32, let unicode = Unicode.Scalar(scalar) else { return false }
            return pane.typeSelect(Character(unicode))
        }
    }

    var isTrashShown: Bool {
        activePane?.currentDirectory.map(Platform.isTrashFolder) ?? false
    }

    /// The focused pane's list widget.
    var focusedListPane: FileListPane? { activeContent?.focusedPane }

    /// A file opens in its default app (as a double-click does in any
    /// Linux file manager).
    func open(_ url: URL) {
        var error: UnsafeMutablePointer<GError>?
        if g_app_info_launch_default_for_uri(url.absoluteString, nil, &error) == 0 {
            let message = error.map { String(cString: $0.pointee.message) } ?? "No app is set to open it."
            if let error { g_error_free(error) }
            showToast("Couldn't open \u{201C}\(url.lastPathComponent)\u{201D}: \(message)")
        }
    }

    // MARK: Sidebar

    private func wireSidebar() {
        // Eject / Disconnect failures: the destinations model keeps the reason.
        destinationErrorWatch = ObservationWatch.watch({ [destinations] in destinations.errorMessage }, emitsInitialValue: false) { [weak self] message in
            guard let self, let message else { return }
            self.destinations.errorMessage = nil
            Dialogs.showError("Couldn\u{2019}t Eject", message, parent: self.window)
        }
        sidebar.onSelect = { [weak self] entry, inNewTab in
            guard let self else { return }
            switch entry {
            case .destination(let destination):
                self.viewModel.selectDestination(destination, inNewTab: inNewTab)
            case .workspace(let workspace):
                self.viewModel.openWorkspace(workspace, inNewTab: inNewTab)
            }
        }
        sidebar.onNewWorkspace = { [weak self] in self?.newWorkspace() }
        sidebar.onBrowseNetwork = { [weak self] in if let self { BrowseNetworkDialog.present(window: self) } }
        sidebar.onContextMenu = { [weak self] entry, row, x, y in self?.showSidebarMenu(entry, row: row, x: x, y: y) }
    }

    // MARK: Toasts

    /// A Settings choice other windows show changed: the address bar style.
    func applySettingsChange() {
        pathBar.applyAddressBarStyle()
    }

    func showToast(_ message: String) {
        let toast = Toast(title: message)
        toast.timeout = 5
        toastOverlay.addToast(toast)
    }

    // MARK: Actions

    private func addActions() {
        func action(_ name: String, _ accels: [String] = [], _ handler: @escaping @MainActor () -> Void) {
            let action = SimpleAction(name: name, handler: handler)
            window.addAction(action)
            if !accels.isEmpty { app.application.setAccelerators(accels, for: "win.\(name)") }
        }
        action("new-tab", ["<Control>t"]) { [weak self] in self?.newTab() }
        addTabActions { name, accels, handler in action(name, accels, handler) }
        action("close-tab", ["<Control>w"]) { [weak self] in
            guard let self else { return }
            if let tab = self.viewModel.activeTab { self.requestCloseTab(tab) } else { self.window.close() }
        }
        action("back", ["<Alt>Left", "Back"]) { [weak self] in self?.activePane?.goBack() }
        action("forward", ["<Alt>Right", "Forward"]) { [weak self] in self?.activePane?.goForward() }
        action("up", ["<Alt>Up"]) { [weak self] in self?.activePane?.goUp() }
        action("home", ["<Alt>Home"]) { [weak self] in
            self?.activePane?.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        }
        action("toggle-dual-pane", ["<Control>backslash"]) { [weak self] in self?.viewModel.toggleSplitActiveTab() }
        action("compare-panes", ["<Control><Alt>backslash"]) { [weak self] in
            guard let tab = self?.viewModel.activeTab, tab.isSplit else {
                self?.showToast("Turn on Dual Pane (Ctrl+\\) to compare two folders")
                return
            }
            tab.comparePanes()
        }
        action("swap-panes", ["<Control><Shift>backslash", "<Control>bar"]) { [weak self] in self?.viewModel.activeTab?.swapPanes() }
        action("switch-pane", ["<Control>grave"]) { [weak self] in
            guard let tab = self?.viewModel.activeTab, tab.isSplit else { return }
            tab.focus(tab.focusedPane == .primary ? .secondary : .primary)
            self?.activeContent?.focusedPane.focus()
        }
        action("reload", ["<Control>r"]) { [weak self] in _ = self?.viewModel.activeTab?.refresh() }
        action("edit-location", ["<Control>l"]) { [weak self] in self?.pathBar.beginEditing() }
        action("find", ["<Control>f"]) { [weak self] in self?.activePane?.focusSearchField() }
        action("advanced-search", ["<Control><Shift>f"]) { [weak self] in
            guard let self else { return }
            self.app.openAdvancedSearch(from: self.activePane?.currentDirectory)
        }
        addWorkspaceActions()
        action("find-duplicates", ["<Control><Shift>d"]) { [weak self] in
            guard let self, let tab = self.viewModel.activeTab else { return }
            var roots: [URL] = []
            for pane in [tab.primary, tab.secondary].compactMap({ $0 }) {
                if let folder = pane.currentDirectory, !roots.contains(folder) { roots.append(folder) }
            }
            guard !roots.isEmpty else { return }
            self.app.openDuplicates(roots: roots)
        }
        action("visualize", ["<Control><Alt>v"]) { [weak self] in self?.visualizePanel.toggle() }
        action("file-operations", ["<Control><Shift>o"]) { [weak self] in self?.operationsPanel.toggle() }
        action("show-hidden", ["<Control>h"]) { [weak self] in self?.activePane?.toggleShowHiddenFiles() }
        let sortBy = SimpleAction(name: "sort-by", parameterType: "s") { [weak self] parameter in
            guard let raw = parameter.stringValue, let field = FileColumn(rawValue: raw) else { return }
            self?.activePane?.setSort(field: field)
        }
        window.addAction(sortBy)
        let toggleColumn = SimpleAction(name: "toggle-column", parameterType: "s") { [weak self] parameter in
            guard let raw = parameter.stringValue, let field = FileColumn(rawValue: raw) else { return }
            self?.activePane?.toggleColumn(field)
        }
        window.addAction(toggleColumn)
        let moveColumn = SimpleAction(name: "move-column", parameterType: "s") { [weak self] parameter in
            guard let raw = parameter.stringValue else { return }
            let parts = raw.split(separator: ":")
            guard parts.count == 2, let field = FileColumn(rawValue: String(parts[0])), let offset = Int(parts[1]) else { return }
            self?.focusedListPane?.moveColumn(field, by: offset)
        }
        window.addAction(moveColumn)
        action("show-all-files") { [weak self] in
            guard let pane = self?.activePane, pane.currentDirectory != nil, pane.virtualLocation == nil else { return }
            pane.setShowsAllFilesInSubfolders(!pane.showsAllFilesInSubfolders)
        }
        action("collapse-folders", ["<Control>minus"]) { [weak self] in self?.hierarchyModel.requestCollapseAll() }
        action("expand-top-level", ["<Control>plus", "<Control>equal"]) { [weak self] in self?.hierarchyModel.requestExpandTopLevel() }
        action("reset-layout") { [weak self] in self?.viewModel.layout.reset() }
        action("eject", ["<Control>j"]) { [weak self] in
            guard let self else { return }
            guard let root = self.viewModel.activeTab?.hierarchyRoot, self.destinations.ejectableURLs.contains(root.url) else {
                self.showToast("Nothing to eject here. Open a removable drive or a network share first.")
                return
            }
            self.destinations.eject(at: root.url)
        }
        action("get-info") { [weak self] in
            guard let self else { return }
            self.viewModel.layout.set(\.showsInspector, true)
            self.showToast("The Inspector shows the details of the selection.")
        }
        action("show-history", ["<Control><Alt>y"]) { [weak self] in self?.app.openHistory() }
        action("recent-locations") { [weak self] in self?.showRecentLocations() }
        action("tools-panel", ["<Control><Alt>b"]) { [weak self] in
            guard let self else { return }
            // The Mac's Tools Panel holds both tools: any open one closes,
            // otherwise File Operations opens.
            if self.operationsPanel.isShown || self.visualizePanel.isShown {
                if self.operationsPanel.isShown { self.operationsPanel.toggle() }
                if self.visualizePanel.isShown { self.visualizePanel.toggle() }
            } else {
                self.operationsPanel.toggle()
            }
        }
        action("columns") { [weak self] in
            guard let self, let pane = self.activePane else { return }
            ColumnsDialog.present(for: pane, over: self.window)
        }
        let groupBy = SimpleAction(name: "group-by", parameterType: "s") { [weak self] parameter in
            guard let raw = parameter.stringValue else { return }
            self?.activePane?.setGroupBy(FileColumn(rawValue: raw))
        }
        window.addAction(groupBy)
        action("view-grid", ["<Control>1"]) { [weak self] in self?.activePane?.setViewMode(.icons) }
        action("view-list", ["<Control>2"]) { [weak self] in self?.activePane?.setViewMode(.list) }
        action("toggle-sidebar", ["F9"]) { [weak self] in self?.viewModel.layout.toggle(\.showsDestinations) }
        action("toggle-hierarchy", ["<Shift>F9"]) { [weak self] in self?.viewModel.layout.toggle(\.showsHierarchy) }
        action("toggle-inspector", ["<Control>i"]) { [weak self] in self?.viewModel.layout.toggle(\.showsInspector) }
    }
}
