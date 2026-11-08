import Combine
import SwiftUI

/// The main window: destinations | (tabs, toolbars, then hierarchy | file
/// list | Inspector), with the status bar and its tools panel along the
/// bottom. Each tab owns its own path/history/sort via its own
/// `FileListViewModel`, and its own hierarchy root; the destination
/// sidebar is shared window chrome, full height beside the tab strip.
///
/// Which panes are shown, and how big, is `WindowViewModel.layout` — saved
/// per window with the session.
struct MainWindowView: View {
    /// Operations already seen, for spotting a new one (see below).
    @State private var knownOperationIDs: Set<UUID> = []
    // Built once per window (see `OwnedModel`).
    @StateObject private var ownedDestinations = OwnedModel(DestinationsViewModel(
        cloudStorageLocations: CloudStorageLocationsService().discover(),
        trashURL: Platform.trashFolder
    ))
    @StateObject private var ownedHierarchy = OwnedModel(FolderHierarchyViewModel(fileWatcher: FileWatcher()))
    @StateObject private var ownedWindow: OwnedModel<WindowViewModel>
    private var destinationsViewModel: DestinationsViewModel { ownedDestinations.value }
    private var hierarchyViewModel: FolderHierarchyViewModel { ownedHierarchy.value }
    private var windowViewModel: WindowViewModel { ownedWindow.value }
    /// The single object the main-menu commands observe (`@FocusedObject`),
    /// published below via `.focusedSceneObject`. Configured in `.onAppear`
    /// once the view models exist. See `WindowMenuState`.
    @StateObject private var menuState = WindowMenuState()
    /// Keeps the hierarchy rooted for the active tab — see the type.
    @State private var hierarchyCoordinator: HierarchyCoordinator?
    @State private var showingConnectSheet = false
    @State private var showingShortcutsQuickView = false
    @State private var hostWindow: NSWindow?
    /// Set only when this window was opened for a torn-off tab (see
    /// `RootView.handoffToken`) — the screen point the drag ended at.
    /// Applied to `hostWindow` the moment `WindowAccessor` resolves it,
    /// then cleared, so a plain window move afterward doesn't keep
    /// snapping back here.
    @State private var pendingWindowOrigin: NSPoint?
    /// Set only when this window reopens a saved one (see `SessionRestorer`)
    /// that remembered where it was — applied once, like `pendingWindowOrigin`.
    @State private var pendingWindowFrame: CGRect?
    @Environment(\.openWindow) private var openWindow

    init(handoffToken: UUID? = nil) {
        let layoutService = WindowLayoutService()
        let newWindowLayout = { WindowLayoutModel(layout: layoutService.load(), service: layoutService) }
        if let handoffToken, let handoff = TabHandoffCenter.shared.take(handoffToken) {
            _ownedWindow = StateObject(wrappedValue: OwnedModel(WindowViewModel(fileWatcherFactory: { FileWatcher() }, layout: newWindowLayout(), startingTab: handoff.tab)))
            _pendingWindowOrigin = State(initialValue: handoff.screenPoint)
            _pendingWindowFrame = State(initialValue: nil)
        } else if let saved = handoffToken.flatMap(SessionRestorer.shared.takeWindow) ?? (handoffToken == nil ? SessionRestorer.shared.takeLaunchWindow() : nil) {
            // A window from the last session: the launch window takes the
            // first one, and the rest arrive here by token.
            _ownedWindow = StateObject(wrappedValue: OwnedModel(WindowViewModel(fileWatcherFactory: { FileWatcher() }, layoutService: layoutService, restoring: saved)))
            _pendingWindowOrigin = State(initialValue: nil)
            _pendingWindowFrame = State(initialValue: saved.frame)
        } else {
            _ownedWindow = StateObject(wrappedValue: OwnedModel(WindowViewModel(fileWatcherFactory: { FileWatcher() }, layout: newWindowLayout())))
            _pendingWindowOrigin = State(initialValue: nil)
            _pendingWindowFrame = State(initialValue: nil)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if let activeTab = windowViewModel.activeTab {
                WindowShell(
                    tab: activeTab,
                    layout: windowViewModel.layout,
                    windowWidth: proxy.size.width,
                    windowViewModel: windowViewModel,
                    destinationsViewModel: destinationsViewModel,
                    hierarchyViewModel: hierarchyViewModel,
                    onConnectToServer: { showingConnectSheet = true }
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $showingConnectSheet) {
            ConnectToServerView { mountPoint in
                windowViewModel.activeTab?.fileListViewModel.navigate(to: mountPoint)
            }
        }
        // Here rather than on the panes, which can be collapsed: a drop on
        // a destination still needs its Replace/Keep Both/Skip prompt.
        .hierarchyAlerts(hierarchyViewModel)
        .alert(
            "Error",
            isPresented: Binding(
                get: { destinationsViewModel.errorMessage != nil },
                set: { isPresented in if !isPresented { destinationsViewModel.errorMessage = nil } }
            ),
            actions: { Button("OK") { destinationsViewModel.errorMessage = nil } },
            message: { Text(destinationsViewModel.errorMessage ?? "") }
        )
        .background {
            Button("New Tab") {
                windowViewModel.openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
            }
            .keyboardShortcut("t", modifiers: .command)
            .hidden()
            Button("Duplicate Tab") {
                windowViewModel.duplicateActiveTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .hidden()
            Button("Close Tab") {
                guard windowViewModel.tabs.count > 1 || CloseLastTabConfirmation.confirm() else { return }
                windowViewModel.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .hidden()
            Button("New Folder") {
                windowViewModel.activeTab?.fileListViewModel.promptForNewFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .hidden()
            Button("New Folder and Open") {
                windowViewModel.activeTab?.fileListViewModel.promptForNewFolderAndOpen()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .hidden()
            Button("New File") {
                windowViewModel.activeTab?.fileListViewModel.promptForNewFile()
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
            Button("Show Hidden Files") {
                windowViewModel.activeTab?.fileListViewModel.toggleShowHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .hidden()
            Button("Back") {
                windowViewModel.activeTab?.fileListViewModel.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .hidden()
            Button("Forward") {
                windowViewModel.activeTab?.fileListViewModel.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .hidden()
            Button("Up") {
                windowViewModel.activeTab?.fileListViewModel.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .hidden()
            Button("Refresh") {
                windowViewModel.activeTab?.refresh()
                hierarchyViewModel.requestRefreshAll()
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
            Button("Collapse All") {
                hierarchyViewModel.requestCollapseAll()
            }
            .keyboardShortcut("-", modifiers: .command)
            .hidden()
            Button("Expand Top Level") {
                hierarchyViewModel.requestExpandTopLevel()
            }
            .keyboardShortcut("+", modifiers: .command)
            .hidden()
            // The old preview pane's shortcut, kept for the Inspector that
            // replaced it (the View menu shows ⌥⌘I).
            Button("Inspector") {
                windowViewModel.layout.toggle(\.showsInspector)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .hidden()
            Button("Connect to Server…") {
                showingConnectSheet = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()
            Button("Keyboard Shortcuts") {
                showingShortcutsQuickView.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            .hidden()
            .popover(isPresented: $showingShortcutsQuickView, arrowEdge: .bottom) {
                ShortcutsQuickView()
            }
            WindowAccessor(window: $hostWindow)
        }
        // ⌘W closes the active tab; once the last tab is gone there's
        // nothing left for this window to show, so close it too (standard
        // ⌘W semantics) instead of the old "always keep one tab open"
        // behavior.
        .onChange(of: windowViewModel.tabs.isEmpty) { _, isEmpty in
            if isEmpty { hostWindow?.close() }
        }
        // Places a tab-handoff window under the point the drag ended at
        // (offset so the dragged tab lands roughly under the cursor,
        // matching Safari/Chrome tear-off) the moment `WindowAccessor`
        // hands back a real `NSWindow` — `openWindow` gives no way to
        // specify a starting frame directly, so this is done as a
        // one-time follow-up move instead.
        // Whether this window shows the File Operations card, so operations
        // started while it's in front skip their floating progress window.
        .onChange(of: windowViewModel.layout.layout.isWorkspaceExpanded) {
            reportCardVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            FileOperationProgressCenter.shared.windowClosed(window.windowNumber)
        }
        // Settings ▸ General ▸ Show progress in the window: a new operation
        // opens this window's File Operations card, if it's the front one,
        // instead of a floating progress window.
        // Only the list of ids, de-duplicated: observing the center itself
        // would redraw the whole window on every progress tick.
        .onChange(of: FileOperationProgressCenter.shared.operationIDs) { _, current in
            let started = !current.subtracting(knownOperationIDs).isEmpty
            knownOperationIDs = current
            let center = FileOperationProgressCenter.shared
            guard started, center.showsProgressInWindow,
                  let number = hostWindow?.windowNumber, center.frontWindowNumber == number
            else { return }
            windowViewModel.showWorkspaceTool(.fileOperations)
        }
        .onChange(of: hostWindow) { _, window in
            guard let window else { return }
            reportCardVisibility()
            if window.isKeyWindow { FileOperationProgressCenter.shared.windowBecameFront(window.windowNumber) }
            SessionRestorer.shared.register(windowViewModel, window: window)
            if let frame = pendingWindowFrame {
                pendingWindowFrame = nil
                window.setFrame(frame, display: true)
            }
            guard let origin = pendingWindowOrigin else { return }
            pendingWindowOrigin = nil
            window.setFrameTopLeftPoint(NSPoint(x: origin.x - 80, y: origin.y + 20))
        }
        // `/` focuses the toolbar's quick-search field, like Slack/Gmail —
        // implemented as `onKeyPress` (not a global `.keyboardShortcut`,
        // which would steal "/" from every text field unconditionally).
        // `onKeyPress` fires before an AppKit-backed text field's own key
        // handling, so typing "/" into the address bar (or any other text
        // field) would otherwise still be swallowed here; guard explicitly
        // against a text field currently editing (its field editor is an
        // `NSTextView`) and let the keystroke fall through to it instead.
        // Only a bare "/": with ⌘, ⌥ or ⌃ it's a menu shortcut (⌘? Help,
        // ⌥⌘/ Advanced Search), which this would otherwise swallow.
        .onKeyPress(KeyEquivalent("/"), phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
            guard !(hostWindow?.firstResponder is NSTextView) else { return .ignored }
            // Next run-loop turn: key presses arrive during SwiftUI's view
            // update, where publishing the focus trigger isn't allowed.
            DispatchQueue.main.async {
                windowViewModel.activeTab?.fileListViewModel.focusSearchField()
            }
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            MainWindowFocusTracker.mostRecentWindowNumber = window.windowNumber
            FileOperationProgressCenter.shared.windowBecameFront(window.windowNumber)
        }
        // "Open in OneRoot" from the Advanced Search window reaches every
        // open main window via this notification; only the one that was
        // most recently key acts on it (falling back to "act anyway" when
        // that's still unset, e.g. only one main window has ever existed).
        // An automatic update check that found a new version (#36).
        .onChange(of: UpdateCenter.shared.presentRequestCount) {
            guard MainWindowFocusTracker.mostRecentWindowNumber == nil
                || hostWindow?.windowNumber == MainWindowFocusTracker.mostRecentWindowNumber else { return }
            openWindow(id: OneRootApp.updateWindowID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealInOneRoot)) { note in
            guard let request = note.object as? RevealInOneRootRequest else { return }
            let isTarget = MainWindowFocusTracker.mostRecentWindowNumber == nil
                || hostWindow?.windowNumber == MainWindowFocusTracker.mostRecentWindowNumber
            guard isTarget else { return }
            if request.openInNewTab {
                windowViewModel.openNewTab(at: request.url)
            } else {
                windowViewModel.activeTab?.fileListViewModel.navigate(to: request.url)
            }
            hostWindow?.makeKeyAndOrderFront(nil)
        }
        // Bridges this window into `OneRootApp`'s main-menu commands
        // (`AppCommands.swift`) through one stable object. A single
        // `focusedSceneObject` — not the old five per-render `focusedSceneValue`s
        // — so re-rendering this view no longer rebuilds the menu bar.
        .focusedSceneObject(menuState)
        .onAppear {
            // Only the launch window has any left to open; for every other
            // window this is a no-op.
            SessionRestorer.shared.openRemainingWindows { token in
                openWindow(id: OneRootApp.tabHandoffWindowID, value: token)
            }
            menuState.configure(windowViewModel: windowViewModel, destinationsViewModel: destinationsViewModel, hierarchyViewModel: hierarchyViewModel)
            // Not while the unit tests run inside the app: no network there.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                UpdateCenter.shared.checkAutomaticallyIfDue()
            }
            if hierarchyCoordinator == nil {
                hierarchyCoordinator = HierarchyCoordinator(windowViewModel: windowViewModel, destinations: destinationsViewModel, hierarchy: hierarchyViewModel)
            }
        }
        // The two window-local surfaces the menus used to trigger via
        // closure-typed focused values; now driven by monotonic counters on
        // `menuState` so nothing volatile lands in the focused-value set.
        .onChange(of: menuState.connectToServerRequestCount) { _, _ in
            showingConnectSheet = true
        }
        .onChange(of: menuState.shortcutsQuickViewRequestCount) { _, _ in
            showingShortcutsQuickView.toggle()
        }
    }

    private func reportCardVisibility() {
        guard let number = hostWindow?.windowNumber else { return }
        FileOperationProgressCenter.shared.setCardShowing(windowViewModel.layout.layout.isWorkspaceExpanded, inWindow: number)
    }
}

/// Grabs the `NSWindow` hosting this SwiftUI view — used here so ⌘W on the
/// last tab can close the actual window instead of leaving an empty shell
/// on screen, and by `SettingsView` to stop macOS restoring a stale window
/// size. Not `MainWindowView`-specific despite living in this file; shared
/// rather than duplicated since it's a plain, self-contained AppKit bridge.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
            // Without this, macOS restores this window's last size/sidebar
            // width from Saved Application State on relaunch, ignoring
            // this view's own initial-size logic entirely (e.g.
            // `PaneSplitViewController`'s initial divider
            // positions, or a `NavigationSplitView`'s ideal frame).
            view.window?.isRestorable = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The whole window for the active tab, in the OneRoot layout: the
/// destination sidebar on the translucent backdrop, full height under the
/// window buttons; to its right the tab strip, the file-list card (path and
/// commands, folder hierarchy, list, status) and the Inspector card; and
/// the tool cards along the bottom. Observes the window's layout, so
/// showing/hiding a pane re-lays out here without `MainWindowView` itself
/// re-rendering.
private struct WindowShell: View {
    var tab: Tab
    var layout: WindowLayoutModel
    let windowWidth: CGFloat
    let windowViewModel: WindowViewModel
    let destinationsViewModel: DestinationsViewModel
    let hierarchyViewModel: FolderHierarchyViewModel
    let onConnectToServer: () -> Void

    var body: some View {
        // What fits: the user's choice, minus panes a narrow window can't
        // hold (Inspector first, then hierarchy, then destinations).
        let shown = layout.layout.fitted(to: windowWidth)
        VStack(spacing: 0) {
            // The tab strip, level with the window's close/minimize/zoom
            // buttons, lined up with the file card below it. It lives up here
            // rather than inside the split's panes: SwiftUI content placed
            // under the (hidden) title bar inside those hosted panes sent
            // AppKit into a layout loop that crashed the app.
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: shown.showsDestinations ? layout.layout.destinationsWidth + 1 : 78)
                TabStripRow(tab: tab, layout: layout, windowViewModel: windowViewModel)
            }
            .frame(height: 40)
            // Drawn over the card's top edge, so the active tab and the card
            // read as one shape (see `TabBarView`).
            .zIndex(1)

            PaneSplitView(panes: [
                PaneSplitView.Pane(
                    content: AnyView(
                        DestinationsSidebarView(
                            destinations: destinationsViewModel,
                            activeTab: tab,
                            activePane: tab.fileListViewModel,
                            hierarchy: hierarchyViewModel,
                            onSelect: { destination, inNewTab in windowViewModel.selectDestination(destination, inNewTab: inNewTab) },
                            onOpenWorkspace: { workspace, inNewTab in windowViewModel.openWorkspace(workspace, inNewTab: inNewTab) },
                            onConnectToServer: onConnectToServer
                        )
                        .themed()
                    ),
                    minWidth: WindowLayout.destinationsWidthRange.lowerBound,
                    maxWidth: WindowLayout.destinationsWidthRange.upperBound,
                    width: layout.layout.destinationsWidth,
                    isCollapsed: !shown.showsDestinations,
                    holdingPriority: 300,
                    // Published, unlike the other widths: the tab strip above
                    // lines up with this pane's edge.
                    onWidthChange: { layout.recordSize(\.destinationsWidth, $0, publishes: true) },
                    onUserCollapse: { layout.set(\.showsDestinations, false) }
                ),
                PaneSplitView.Pane(
                    content: AnyView(
                        TabContentView(
                            tab: tab,
                            layout: layout,
                            shown: shown,
                            windowViewModel: windowViewModel,
                            hierarchyViewModel: hierarchyViewModel
                        )
                        .themed()
                    ),
                    minWidth: WindowLayout.minimumListWidth
                        + (shown.showsHierarchy ? WindowLayout.hierarchyWidthRange.lowerBound : 0)
                        + (shown.showsInspector ? WindowLayout.inspectorWidthRange.lowerBound : 0),
                    holdingPriority: 200
                ),
            ], transparentDividers: true)

            if layout.layout.isWorkspaceExpanded {
                ToolCardsView(tab: tab, layout: layout, windowViewModel: windowViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background { WindowBackdrop().ignoresSafeArea() }
        .ignoresSafeArea(.container, edges: .top)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.2), value: layout.layout.isWorkspaceExpanded)
    }
}

/// The active tab's content under the tab strip: the file-list card and the
/// Inspector card. Everything acts
/// on the focused pane (`tab.fileListViewModel`).
private struct TabContentView: View {
    var tab: Tab
    var layout: WindowLayoutModel
    let shown: WindowLayout
    let windowViewModel: WindowViewModel
    let hierarchyViewModel: FolderHierarchyViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            PaneSplitView(panes: [
                PaneSplitView.Pane(
                    content: AnyView(fileCard.themed()),
                    minWidth: WindowLayout.minimumListWidth
                        + (shown.showsHierarchy ? WindowLayout.hierarchyWidthRange.lowerBound : 0),
                    holdingPriority: 200
                ),
                PaneSplitView.Pane(
                    content: AnyView(
                        InspectorContainerView(tab: tab, isVisible: shown.showsInspector)
                            .card()
                            .padding(.leading, 4)
                            .padding([.trailing, .bottom], 10)
                            .themed()
                    ),
                    minWidth: WindowLayout.inspectorWidthRange.lowerBound,
                    maxWidth: WindowLayout.inspectorWidthRange.upperBound,
                    width: layout.layout.inspectorWidth,
                    isCollapsed: !shown.showsInspector,
                    holdingPriority: 290,
                    onWidthChange: { layout.recordSize(\.inspectorWidth, $0) },
                    onUserCollapse: { layout.set(\.showsInspector, false) }
                ),
            ], transparentDividers: true)
        }
    }

    /// Path and commands, then the folder hierarchy beside the list (one
    /// card, the way they work together), then the status line.
    private var fileCard: some View {
        VStack(spacing: 0) {
            ShortcutToolbarView(
                viewModel: tab.fileListViewModel,
                layout: layout,
                workspace: tab.workspaceID.flatMap(WorkspaceStore.shared.workspace),
                isDualPane: tab.isSplit,
                onToggleDualPane: { windowViewModel.toggleSplitActiveTab() },
                isComparing: tab.comparison != nil,
                onComparePanes: {
                    if let comparison = tab.comparison { comparison.end() } else { tab.comparePanes() }
                },
                onRefresh: {
                    tab.refresh()
                    hierarchyViewModel.requestRefreshAll()
                }
            )
            Divider()
            PaneSplitView(panes: [
                PaneSplitView.Pane(
                    content: AnyView(
                        FolderHierarchyView(
                            viewModel: hierarchyViewModel,
                            onSelect: { node in tab.fileListViewModel.navigate(to: node.url) },
                            onOpenInNewTab: { node in windowViewModel.openNewTab(at: node.url) }
                        )
                        .themed()
                    ),
                    minWidth: WindowLayout.hierarchyWidthRange.lowerBound,
                    maxWidth: WindowLayout.hierarchyWidthRange.upperBound,
                    width: layout.layout.hierarchyWidth,
                    isCollapsed: !shown.showsHierarchy,
                    holdingPriority: 300,
                    onWidthChange: { layout.recordSize(\.hierarchyWidth, $0) },
                    onUserCollapse: { layout.set(\.showsHierarchy, false) }
                ),
                PaneSplitView.Pane(
                    content: AnyView(primaryPane.themed()),
                    minWidth: WindowLayout.minimumListWidth,
                    holdingPriority: 200
                ),
            ])
            Divider()
            OperationErrorBanner(viewModel: tab.fileListViewModel, windowViewModel: windowViewModel)
            CardStatusBar(viewModel: tab.fileListViewModel, layout: layout, windowViewModel: windowViewModel)
        }
        .card(squareTopLeading: true)
        .padding(.trailing, 4)
        .padding(.bottom, 10)
    }

    /// The file list — or, with Dual Pane on, two side by side, each with
    /// a header showing which one has focus.
    @ViewBuilder
    private var primaryPane: some View {
        if let secondary = tab.secondary {
            VStack(spacing: 0) {
                if let comparison = tab.comparison {
                    PaneComparisonBar(comparison: comparison)
                    Divider()
                }
                HStack(spacing: 0) {
                    headedPane(tab.primary, .primary, other: secondary)
                    Divider()
                    headedPane(secondary, .secondary, other: tab.primary)
                }
            }
        } else {
            TabFileList(tab: tab, viewModel: tab.primary, other: nil, pane: .primary, windowViewModel: windowViewModel)
        }
    }

    private func headedPane(_ viewModel: FileListViewModel, _ pane: Pane, other: FileListViewModel) -> some View {
        VStack(spacing: 0) {
            PaneHeaderBar(
                tab: tab,
                pane: pane,
                viewModel: viewModel,
                isFocused: tab.focusedPane == pane,
                onTearOff: tearOff
            )
            .frame(height: 22)
            Divider()
            TabFileList(tab: tab, viewModel: viewModel, other: other, pane: pane, windowViewModel: windowViewModel)
        }
        .frame(maxWidth: .infinity)
    }
}

extension TabContentView {
    /// A pane dragged out of the window: it becomes a single-pane tab in a
    /// new window there, through the same handoff a torn-off tab uses.
    fileprivate func tearOff(_ viewModel: FileListViewModel, at screenPoint: NSPoint) {
        let token = TabHandoffCenter.shared.store(Tab(fileListViewModel: viewModel), screenPoint: screenPoint)
        openWindow(id: OneRootApp.tabHandoffWindowID, value: token)
    }
}

/// One of the active tab's file panes.
private struct TabFileList: View {
    let tab: Tab
    let viewModel: FileListViewModel
    let other: FileListViewModel?
    let pane: Pane
    let windowViewModel: WindowViewModel

    var body: some View {
        FileListView(viewModel: viewModel, otherPane: other, onFocus: { [tab] in tab.focus(pane) }) { url, openInNewTab in
            if openInNewTab {
                windowViewModel.openNewTab(at: url)
            } else {
                viewModel.navigate(to: url)
            }
        }
        // A fresh table per pane: otherwise SwiftUI hands the same
        // `NSTableView` from one tab to the next, so the selection shown
        // and the one menus act on (`selectedNodes`) could disagree.
        .id(ObjectIdentifier(viewModel))
    }
}

#Preview {
    MainWindowView()
}
