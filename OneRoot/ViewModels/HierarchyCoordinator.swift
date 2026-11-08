import Foundation

/// Keeps one window's folder hierarchy rooted and in step with its active
/// tab: works out each tab's `HierarchyRoot` as it browses (via
/// `HierarchyRootResolver`), hands the active one to
/// `FolderHierarchyViewModel`, and reveals the current folder in the tree.
/// Also feeds the hierarchy the destination state it needs (which roots
/// can be ejected, and how).
///
/// A plain object rather than more `MainWindowView` state, so navigating
/// never re-renders the window — the job `WindowMenuState` used to do for
/// the old tree's reveal.
@MainActor
final class HierarchyCoordinator {
    private let windowViewModel: WindowViewModel
    private let destinations: DestinationsViewModel
    private let hierarchy: FolderHierarchyViewModel
    private let workspaces: WorkspaceStore
    private var activeTabWatch: ObservationWatch?
    private var tabWatch: ObservationWatch?
    private var workspacesWatch: ObservationWatch?
    private var sectionsWatch: ObservationWatch?

    init(
        windowViewModel: WindowViewModel,
        destinations: DestinationsViewModel,
        hierarchy: FolderHierarchyViewModel,
        workspaces: WorkspaceStore? = nil
    ) {
        self.windowViewModel = windowViewModel
        self.destinations = destinations
        self.hierarchy = hierarchy
        self.workspaces = workspaces ?? .shared

        hierarchy.ejectHandler = { [weak destinations] url in destinations?.eject(at: url) }

        activeTabWatch = ObservationWatch.watch({ windowViewModel.activeTabID }, emitsInitialValue: false) { [weak self] _ in
            self?.watchActiveTab()
        }
        sectionsWatch = ObservationWatch.watch({ destinations.sections }, emitsInitialValue: false) { [weak self] _ in
            self?.destinationsChanged()
        }
        // A Workspace's folders edited (or the Workspace deleted).
        let workspaceStore = self.workspaces
        workspacesWatch = ObservationWatch.watch({ workspaceStore.workspaces }, emitsInitialValue: false) { [weak self] _ in
            self?.syncActiveTab(reveal: false)
        }

        destinationsChanged()
        watchActiveTab()
    }

    private func destinationsChanged() {
        hierarchy.updateEjectableRootURLs(destinations.ejectableURLs)
        syncActiveTab(reveal: false)
    }

    private func watchActiveTab() {
        tabWatch?.cancel()
        tabWatch = nil
        guard let tab = windowViewModel.activeTab else { return }
        // Splitting or moving focus between panes changes which pane's
        // folder the hierarchy follows; so does choosing a destination or
        // a Workspace.
        tabWatch = ObservationWatch.watch({
            _ = (tab.primary, tab.secondary, tab.focusedPane, tab.hierarchyRoot, tab.workspaceID)
        }, emitsInitialValue: false) { [weak self] in
            self?.rebindFocusedPane()
        }
        rebindFocusedPane()
    }

    private var focusedPaneWatch: ObservationWatch?
    private var focusedPaneListWatch: ObservationWatch?
    private var focusedPaneShowsList: Bool?
    private weak var focusedPane: FileListViewModel?

    private func rebindFocusedPane() {
        let pane = windowViewModel.activeTab?.fileListViewModel
        // Any other tab change (its root being set) just re-syncs; the
        // pane's own `$currentDirectory` below does the revealing, and
        // replays its current value on subscribe.
        guard pane !== focusedPane else {
            syncActiveTab(reveal: false)
            return
        }
        focusedPane = pane
        focusedPaneWatch?.cancel()
        focusedPaneListWatch?.cancel()
        focusedPaneWatch = nil
        focusedPaneListWatch = nil
        focusedPaneShowsList = nil
        guard let pane else { return }
        focusedPaneWatch = ObservationWatch.watch({ pane.currentDirectory }) { [weak self] _ in
            self?.syncActiveTab(reveal: true)
        }
        // Recents and Shared aren't inside any folder: the hierarchy
        // closes while one is shown, and comes back after.
        focusedPaneListWatch = ObservationWatch.watch({ pane.virtualLocation != nil }) { [weak self] showsList in
            guard let self, self.focusedPaneShowsList != showsList else { return }
            self.focusedPaneShowsList = showsList
            self.windowViewModel.setShowingList(showsList)
        }
    }

    /// Roots the active tab (if its folder has left its root, or the root
    /// stopped being a destination), shows that root in the tree, and
    /// reveals the folder.
    private func syncActiveTab(reveal: Bool) {
        guard let tab = windowViewModel.activeTab,
              let location = tab.fileListViewModel.currentDirectory else { return }
        // In a Workspace: all its folders, for as long as the tab stays in
        // one of them. Leaving them (or the Workspace going) ends it.
        if let id = tab.workspaceID {
            if let workspace = workspaces.workspace(id), workspace.contains(location) {
                hierarchy.setRoots(workspace.hierarchyRoots)
                if reveal { hierarchy.reveal(location) }
                return
            }
            tab.workspaceID = nil
        }
        let root: HierarchyRoot
        if destinations.hasLoadedVolumes {
            root = HierarchyRootResolver.root(for: location, current: tab.hierarchyRoot, candidates: destinations.hierarchyCandidates)
            if tab.hierarchyRoot != root { tab.hierarchyRoot = root }
        } else {
            // Volumes arrive asynchronously at launch. Until then a saved
            // root on an external drive can't be checked, so show it as-is
            // (or a provisional one) without storing a guess on the tab.
            root = tab.hierarchyRoot.flatMap { $0.contains(location) ? $0 : nil }
                ?? HierarchyRootResolver.root(for: location, current: nil, candidates: destinations.hierarchyCandidates)
        }
        hierarchy.setRoots([root])
        if reveal { hierarchy.reveal(location) }
    }
}
