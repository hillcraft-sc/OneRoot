import Foundation
import Observation

@MainActor
@Observable
final class WindowViewModel {
    private(set) var tabs: [Tab] = []
    private(set) var activeTabID: Tab.ID?
    /// This window's panes — saved with the session. Its own
    /// `ObservableObject`, so a pane toggle doesn't re-render everything
    /// observing the tabs.
    let layout: WindowLayoutModel

    private let fileSystemService: FileSystemService
    /// A factory, not a shared instance — each tab watches its own current
    /// directory independently. Defaults to inert so tests don't each spin
    /// up real FSEvents streams; `MainWindowView` injects a real
    /// `FileWatcher` factory.
    private let fileWatcherFactory: () -> FileWatching
    /// Handed to every tab's `FileListViewModel` so they all feed the one
    /// app-wide browsing history. Injectable so tests get an isolated one
    /// instead of writing temp-dir paths into `UserDefaults.standard`.
    private let navigationHistory: NavigationHistoryStore

    init(
        fileSystemService: FileSystemService = FileSystemService(),
        fileWatcherFactory: @escaping () -> FileWatching = { NullFileWatcher() },
        navigationHistory: NavigationHistoryStore? = nil,
        layout: WindowLayoutModel? = nil,
        startingTab: Tab? = nil,
        opensDefaultTab: Bool = true
    ) {
        self.layout = layout ?? WindowLayoutModel(layout: WindowLayout())
        self.fileSystemService = fileSystemService
        self.fileWatcherFactory = fileWatcherFactory
        self.navigationHistory = navigationHistory ?? .shared
        if let startingTab {
            // A tab torn off from another window arrives fully formed
            // (its own history/sort state intact) — seed with it directly
            // instead of `openNewTab`'s fresh-home-directory tab.
            tabs = [startingTab]
            activeTabID = startingTab.id
        } else if opensDefaultTab {
            openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    /// A window reopened from the last session (see `SessionRestorer`):
    /// its tabs, splits, folders, and sort orders, with the same tab active.
    convenience init(
        fileSystemService: FileSystemService = FileSystemService(),
        fileWatcherFactory: @escaping () -> FileWatching = { NullFileWatcher() },
        navigationHistory: NavigationHistoryStore? = nil,
        layoutService: WindowLayoutService? = nil,
        restoring saved: SavedWindow
    ) {
        let layout = WindowLayoutModel(layout: saved.layout ?? layoutService?.load() ?? WindowLayout(), service: layoutService)
        self.init(fileSystemService: fileSystemService, fileWatcherFactory: fileWatcherFactory, navigationHistory: navigationHistory, layout: layout, startingTab: nil, opensDefaultTab: false)
        for savedTab in saved.tabs {
            let secondary = savedTab.secondary.map(restorePane)
            tabs.append(Tab(
                primary: restorePane(savedTab.primary),
                secondary: secondary,
                focusedPane: savedTab.secondaryHasFocus ? .secondary : .primary,
                hierarchyRoot: savedTab.hierarchyRoot,
                inspectorSection: savedTab.inspectorSection ?? .details,
                workspaceID: savedTab.workspaceID
            ))
        }
        if tabs.isEmpty {
            openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
        } else {
            activeTabID = tabs[min(max(saved.activeTabIndex, 0), tabs.count - 1)].id
        }
    }

    private func restorePane(_ saved: SavedPane) -> FileListViewModel {
        let pane = makeFileListViewModel()
        if let field = FileColumn(rawValue: saved.sortField) {
            pane.restoreSort(field: field, ascending: saved.sortAscending)
        }
        let url = URL(string: saved.path).flatMap(VirtualLocation.init(url:))?.url
            ?? URL(fileURLWithPath: saved.path, isDirectory: true)
        pane.navigate(to: url, recordHistory: false)
        return pane
    }

    /// This window's tabs as they stand, for saving with the session.
    func savedState(frame: CGRect?) -> SavedWindow {
        func save(_ pane: FileListViewModel) -> SavedPane {
            SavedPane(
                // Recents/Shared are saved as their `oneroot:` URL.
                path: pane.virtualLocation?.url.absoluteString
                    ?? (pane.currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser).path,
                sortField: pane.sortField.rawValue,
                sortAscending: pane.sortDirection == .ascending
            )
        }
        return SavedWindow(
            frame: frame,
            tabs: tabs.map { tab in
                SavedTab(
                    primary: save(tab.primary),
                    secondary: tab.secondary.map(save),
                    secondaryHasFocus: tab.isSplit && tab.focusedPane == .secondary,
                    hierarchyRoot: tab.hierarchyRoot,
                    inspectorSection: tab.inspectorSection,
                    workspaceID: tab.workspaceID
                )
            },
            activeTabIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0,
            layout: layout.layout
        )
    }

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    private func makeFileListViewModel() -> FileListViewModel {
        FileListViewModel(fileSystemService: fileSystemService, fileWatcher: fileWatcherFactory(), navigationHistory: navigationHistory)
    }

    /// `root` roots the new tab's folder hierarchy there (a destination
    /// opened in a new tab); otherwise it's worked out from `url`.
    @discardableResult
    func openNewTab(at url: URL, root: HierarchyRoot? = nil, makeActive: Bool = true) -> Tab {
        let tab = Tab(fileListViewModel: makeFileListViewModel())
        tab.hierarchyRoot = root
        tab.fileListViewModel.navigate(to: url)
        tabs.append(tab)
        if makeActive {
            activeTabID = tab.id
        }
        return tab
    }

    /// Closing the last tab leaves `tabs` empty on purpose — ⌘W then closes
    /// the window itself (see `MainWindowView`), matching standard macOS
    /// "close tab, then close window" semantics instead of forcing a window
    /// to always show something.
    func closeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)

        guard activeTabID == tab.id else { return }
        activeTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    func closeActiveTab() {
        guard let tab = activeTab else { return }
        closeTab(tab)
    }

    /// Closes every tab but `tab`, which becomes the active one. Never
    /// closes the window, so it needs no confirmation.
    func closeOtherTabs(keeping tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        tabs = [tab]
        activeTabID = tab.id
    }

    /// Closes the tabs after `tab` in the strip. The active tab moves to
    /// `tab` if it was one of those closed.
    func closeTabsToTheRight(of tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }), index < tabs.count - 1 else { return }
        let closing = Set(tabs[(index + 1)...].map(\.id))
        tabs.removeSubrange((index + 1)...)
        if let activeTabID, closing.contains(activeTabID) { self.activeTabID = tab.id }
    }

    /// Whether any tab comes after `tab` — Close Tabs to the Right.
    func hasTabs(after tab: Tab) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return false }
        return index < tabs.count - 1
    }

    /// View ▸ Show Next Tab (⌃⇥) / Show Previous Tab (⌃⇧⇥), wrapping round
    /// at the ends as Finder and Safari do.
    func selectAdjacentTab(_ offset: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let next = ((index + offset) % tabs.count + tabs.count) % tabs.count
        activeTabID = tabs[next].id
    }

    /// Opens a new tab at the active tab's current location, right after it.
    /// Only the location carries over — like "Open in New Tab", the new tab
    /// starts with fresh history rather than cloning the back/forward stack.
    func duplicateActiveTab() {
        guard let tab = activeTab, let url = tab.fileListViewModel.currentLocationURL else { return }
        let newTab = Tab(fileListViewModel: makeFileListViewModel())
        newTab.hierarchyRoot = tab.hierarchyRoot
        newTab.inspectorSection = tab.inspectorSection
        newTab.workspaceID = tab.workspaceID
        newTab.fileListViewModel.navigate(to: url)
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.insert(newTab, at: index + 1)
        } else {
            tabs.append(newTab)
        }
        activeTabID = newTab.id
    }

    /// Chooses a destination in the sidebar: roots the active tab's folder
    /// hierarchy there and goes to it — or does both in a new tab.
    func selectDestination(_ destination: Destination, inNewTab: Bool = false) {
        // Recents/Shared: show the list, and leave the hierarchy as it is.
        if destination.kind.isVirtual {
            if inNewTab || activeTab == nil {
                openNewTab(at: destination.url, root: activeTab?.hierarchyRoot)
            } else {
                activeTab?.fileListViewModel.navigate(to: destination.url)
            }
            return
        }
        if destination.kind == .trash { Platform.ensureTrashFolderExists() }
        guard !inNewTab, let tab = activeTab else {
            openNewTab(at: destination.url, root: destination.hierarchyRoot)
            return
        }
        // Root first, so the coordinator sees the new location is inside
        // it and keeps it rather than picking another.
        tab.workspaceID = nil
        tab.hierarchyRoot = destination.hierarchyRoot
        tab.fileListViewModel.navigate(to: destination.url)
    }

    /// Works in `workspace`: its folders become the hierarchy's roots, and
    /// the tab goes to the first one that's there (a drive can be
    /// unplugged).
    func openWorkspace(_ workspace: Workspace, inNewTab: Bool = false) {
        guard let folder = workspace.folders.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? workspace.folders.first else { return }
        let tab: Tab
        if inNewTab || activeTab == nil {
            tab = Tab(fileListViewModel: makeFileListViewModel())
            tabs.append(tab)
            activeTabID = tab.id
        } else if let active = activeTab {
            tab = active
        } else {
            return
        }
        // Workspace first, so the coordinator keeps it for the new folder.
        tab.workspaceID = workspace.id
        tab.fileListViewModel.navigate(to: folder)
    }

    /// View ▸ Split Pane (⌘\): splits the active tab into two panes, or
    /// closes the split (keeping the focused pane).
    func toggleSplitActiveTab() {
        guard let tab = activeTab else { return }
        if tab.isSplit {
            tab.unsplit()
        } else {
            tab.split(makePane: makeFileListViewModel)
        }
    }

    // MARK: Bottom workspace

    func showWorkspaceTool(_ tool: WorkspaceTool) {
        layout.set(\.workspaceTool, tool)
        setWorkspaceExpanded(true)
    }

    /// Whether the hierarchy was open before Recents/Shared closed it — so
    /// it comes back after, but not if you'd closed it yourself.
    @ObservationIgnored private var hierarchyClosedForList = false

    /// Recents or Shared shown (`true`) or left: closes the folder
    /// hierarchy for the list and reopens it afterwards. Opening it again
    /// by hand while in the list is respected.
    func setShowingList(_ showsList: Bool) {
        if showsList {
            guard layout.layout.showsHierarchy else { return }
            hierarchyClosedForList = true
            layout.set(\.showsHierarchy, false)
        } else if hierarchyClosedForList {
            hierarchyClosedForList = false
            layout.set(\.showsHierarchy, true)
        }
    }

    /// Collapsing never cancels anything — operations keep running.
    func setWorkspaceExpanded(_ expanded: Bool) {
        layout.set(\.isWorkspaceExpanded, expanded)
    }

    func selectWorkspaceTool(_ tool: WorkspaceTool) {
        layout.set(\.workspaceTool, tool)
    }

    /// Copies or moves the focused pane's selection into the other pane's
    /// folder — File ▸ Copy/Move to Other Pane. Goes through the focused
    /// pane's own drop handling, same as the views' F5/F6, so it gets the
    /// conflict prompt, progress window, and Undo.
    @discardableResult
    func sendSelectionToOtherPane(move: Bool) -> Task<Void, Never>? {
        guard let tab = activeTab,
              let destination = tab.otherPane?.currentDirectory else { return nil }
        let source = tab.fileListViewModel
        let urls = source.selectedNodes.map(\.url)
        guard !urls.isEmpty else { return nil }
        return source.handleDrop(urls: urls, into: destination, move: move)
    }

    func selectTab(_ tab: Tab) {
        activeTabID = tab.id
    }

    /// Reorders `tab` to `destinationIndex` within this window's tab strip
    /// — the drag-to-reorder half of tab drag-and-drop.
    func moveTab(_ tab: Tab, to destinationIndex: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        var reordered = tabs
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: min(max(destinationIndex, 0), reordered.count))
        tabs = reordered
    }

    /// Removes `tab` for handoff elsewhere (a new window via tear-off, or
    /// another window's tab bar) — unlike `closeTab`, this isn't a user
    /// "close" action, just relocation, though it shares the same "last
    /// tab gone" result: `MainWindowView` still closes the now-empty
    /// window, matching what dragging the last tab out of a window does
    /// in Safari/Chrome.
    func detachTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        guard activeTabID == tab.id else { return }
        activeTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    /// File ▸ Move Tab to New Window (⌃⌘T): takes the active tab out of this
    /// window and returns it, for the caller to hand to a new window — the
    /// keyboard version of dragging it off the tab bar. `nil` (and nothing
    /// changes) with only one tab: moving a window's only tab would just
    /// recreate the window.
    func detachActiveTabForNewWindow() -> Tab? {
        guard tabs.count > 1, let tab = activeTab else { return nil }
        detachTab(tab)
        return tab
    }

    /// Inserts a tab handed off from another window's tab bar (drag-in
    /// from another window, or a tear-off dropped back onto a tab strip)
    /// at `index`, making it active.
    func insertTab(_ tab: Tab, at index: Int) {
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        activeTabID = tab.id
    }
}
