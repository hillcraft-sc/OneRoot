import Combine
import Foundation

/// The single, stable object every main-menu command reads from.
///
/// Before this, `MainWindowView` published five separate `focusedSceneValue`s
/// — two of them freshly allocated closures — and re-applied all five on every
/// `body` pass (which happens on every navigation and every FSEvents tick).
/// Each re-application changed the focused-value set, so SwiftUI rebuilt the
/// whole `.commands` tree and, with it, the AppKit menu bar. Rebuilding an open
/// `NSMenu` is what made every menu flicker, self-close, and occasionally drop
/// items — a submenu that tracks the pointer (Recent Locations) just made it
/// impossible to miss.
///
/// Now there is one `@FocusedObject`. It hands the command *actions* the
/// underlying view models by reference, and mirrors only the handful of values
/// the menus actually *display* (`canGoBack`, selection count, …) as
/// `@Published`, each guarded so it publishes on a real change. Commands
/// re-render exactly when a value they show changes, never merely because a
/// window re-rendered.
///
/// Created once per window as a `@StateObject` in `MainWindowView`, which calls
/// `configure(...)` once its own view models exist.
@MainActor
final class WindowMenuState: ObservableObject {
    /// `nil` until `configure(...)` runs. Commands guard on it the same way
    /// they used to guard on a `nil` `@FocusedValue`.
    private(set) var windowViewModel: WindowViewModel?
    private(set) var destinationsViewModel: DestinationsViewModel?
    private(set) var hierarchyViewModel: FolderHierarchyViewModel?

    @Published private(set) var fileListViewModel: FileListViewModel?

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var canGoUp = false
    @Published private(set) var selectionCount = 0
    /// View ▸ Clear Filters / Search Subfolders with This Filter.
    @Published private(set) var hasFilter = false
    /// File ▸ Quick Actions — what applies to the selection.
    @Published private(set) var quickActions: [QuickActionOption] = []
    @Published private(set) var showHiddenFiles = false
    @Published private(set) var showsAllFilesInSubfolders = false
    @Published private(set) var viewMode: FileViewMode = .list
    @Published private(set) var isSplit = false
    @Published private(set) var tabCount = 0
    /// Whether the active tab is the last in the strip — View ▸ Close Tabs
    /// to the Right has nothing to close then.
    @Published private(set) var activeTabIsLast = true
    /// The active tab is rooted at an ejectable volume or share — what
    /// File ▸ Eject (⌘J) acts on.
    @Published private(set) var activeRootIsEjectable = false
    @Published private(set) var showsDestinations = true
    @Published private(set) var showsHierarchy = true
    @Published private(set) var showsInspector = false
    @Published private(set) var isWorkspaceExpanded = false
    @Published private(set) var recentLocations: [URL] = []

    /// Monotonic triggers the two window-local sheets/popovers watch with
    /// `.onChange` — same pattern as `FolderHierarchyViewModel.collapseAllRequestCount`.
    /// A closure stored as a focused value was the original churn source; the
    /// action lives on this stable object instead.
    @Published private(set) var connectToServerRequestCount = 0
    @Published private(set) var shortcutsQuickViewRequestCount = 0

    private let history: NavigationHistoryStore
    private var windowWatches: [ObservationWatch] = []
    private var historyWatch: ObservationWatch?
    private var sectionsWatch: ObservationWatch?
    private var layoutWatch: ObservationWatch?
    private var activeTabWatches: [ObservationWatch] = []
    /// Watches the active `Tab` itself — splitting, or focus moving between
    /// its panes, changes which `FileListViewModel` is "current".
    private var tabWatch: ObservationWatch?
    private var configured = false

    /// `nil` means the shared store — a default argument of `.shared` would
    /// be evaluated outside the main actor.
    init(history: NavigationHistoryStore? = nil) {
        let history = history ?? .shared
        self.history = history
        self.recentLocations = history.entries
        historyWatch = ObservationWatch.watch({ history.entries }, emitsInitialValue: false) { [weak self] entries in
            guard let self, self.recentLocations != entries else { return }
            self.recentLocations = entries
        }
    }

    func configure(windowViewModel: WindowViewModel, destinationsViewModel: DestinationsViewModel, hierarchyViewModel: FolderHierarchyViewModel) {
        guard !configured else { return }
        configured = true
        self.windowViewModel = windowViewModel
        self.destinationsViewModel = destinationsViewModel
        self.hierarchyViewModel = hierarchyViewModel

        windowWatches.append(ObservationWatch.watch({ windowViewModel.activeTabID }, emitsInitialValue: false) { [weak self] _ in
            self?.watchActiveTab()
        })

        sectionsWatch = ObservationWatch.watch({ destinationsViewModel.sections }, emitsInitialValue: false) { [weak self] _ in
            self?.refreshEjectMirror()
        }
        let layout = windowViewModel.layout
        layoutWatch = ObservationWatch.watch({ layout.layout }, emitsInitialValue: false) { [weak self] _ in
            self?.refreshLayoutMirrors()
        }

        windowWatches.append(ObservationWatch.watch({ windowViewModel.tabs.count }) { [weak self] count in
            self?.setIfChanged(\.tabCount, count)
        })
        windowWatches.append(ObservationWatch.watch({ windowViewModel.tabs.last?.id == windowViewModel.activeTabID }) { [weak self] isLast in
            self?.setIfChanged(\.activeTabIsLast, isLast)
        })

        watchActiveTab()
        refreshEjectMirror()
        refreshLayoutMirrors()
    }

    private func watchActiveTab() {
        tabWatch?.cancel()
        tabWatch = nil
        if let tab = windowViewModel?.activeTab {
            tabWatch = ObservationWatch.watch({
                _ = (tab.primary, tab.secondary, tab.focusedPane, tab.hierarchyRoot)
            }, emitsInitialValue: false) { [weak self] in
                self?.rebindActiveTab()
            }
        }
        rebindActiveTab()
    }

    func requestConnectToServer() { connectToServerRequestCount &+= 1 }
    func requestShortcutsQuickView() { shortcutsQuickViewRequestCount &+= 1 }

    // MARK: Active tab

    private func rebindActiveTab() {
        setIfChanged(\.isSplit, windowViewModel?.activeTab?.isSplit ?? false)
        refreshEjectMirror()
        let flvm = windowViewModel?.activeTab?.fileListViewModel
        guard fileListViewModel !== flvm || activeTabWatches.isEmpty else { return }
        if fileListViewModel !== flvm { fileListViewModel = flvm }
        activeTabWatches.forEach { $0.cancel() }
        activeTabWatches.removeAll()

        guard let flvm else {
            refreshNavigationMirrors(nil)
            return
        }

        // Back/Forward/Up follow the folder and the history stacks.
        activeTabWatches.append(ObservationWatch.watch({
            _ = (flvm.currentDirectory, flvm.canGoBack, flvm.canGoForward, flvm.virtualLocation)
        }, emitsInitialValue: false) { [weak self, weak flvm] in
            self?.refreshNavigationMirrors(flvm)
        })
        activeTabWatches.append(ObservationWatch.watch({ flvm.selectedNodes }, emitsInitialValue: false) { [weak self, weak flvm] nodes in
            self?.setIfChanged(\.selectionCount, nodes.count)
            self?.setIfChanged(\.quickActions, flvm?.quickActionOptions(for: nodes) ?? [])
        })
        activeTabWatches.append(ObservationWatch.watch({ flvm.filter.hasFilters }, emitsInitialValue: false) { [weak self] value in
            self?.setIfChanged(\.hasFilter, value)
        })
        activeTabWatches.append(ObservationWatch.watch({ flvm.showHiddenFiles }, emitsInitialValue: false) { [weak self] value in
            self?.setIfChanged(\.showHiddenFiles, value)
        })
        activeTabWatches.append(ObservationWatch.watch({ flvm.showsAllFilesInSubfolders }, emitsInitialValue: false) { [weak self] value in
            self?.setIfChanged(\.showsAllFilesInSubfolders, value)
        })
        activeTabWatches.append(ObservationWatch.watch({ flvm.viewMode }, emitsInitialValue: false) { [weak self] value in
            self?.setIfChanged(\.viewMode, value)
        })

        refreshNavigationMirrors(flvm)
    }

    private func refreshNavigationMirrors(_ flvm: FileListViewModel?) {
        setIfChanged(\.canGoBack, flvm?.canGoBack ?? false)
        setIfChanged(\.canGoForward, flvm?.canGoForward ?? false)
        setIfChanged(\.canGoUp, flvm?.canGoUp ?? false)
        setIfChanged(\.selectionCount, flvm?.selectedNodes.count ?? 0)
        setIfChanged(\.quickActions, flvm.map { $0.quickActionOptions(for: $0.selectedNodes) } ?? [])
        setIfChanged(\.showHiddenFiles, flvm?.showHiddenFiles ?? false)
        setIfChanged(\.showsAllFilesInSubfolders, flvm?.showsAllFilesInSubfolders ?? false)
        setIfChanged(\.hasFilter, flvm?.filter.hasFilters ?? false)
        setIfChanged(\.viewMode, flvm?.viewMode ?? .list)
    }

    private func refreshEjectMirror() {
        let ejectable: Bool
        if let root = windowViewModel?.activeTab?.hierarchyRoot, let destinations = destinationsViewModel {
            ejectable = destinations.ejectableURLs.contains(root.url)
        } else {
            ejectable = false
        }
        setIfChanged(\.activeRootIsEjectable, ejectable)
    }

    private func refreshLayoutMirrors() {
        guard let layout = windowViewModel?.layout.layout else { return }
        setIfChanged(\.showsDestinations, layout.showsDestinations)
        setIfChanged(\.showsHierarchy, layout.showsHierarchy)
        setIfChanged(\.showsInspector, layout.showsInspector)
        setIfChanged(\.isWorkspaceExpanded, layout.isWorkspaceExpanded)
    }

    /// File ▸ Eject (⌘J): the volume or share the active tab is rooted at.
    func ejectActiveRoot() {
        guard let root = windowViewModel?.activeTab?.hierarchyRoot else { return }
        destinationsViewModel?.eject(at: root.url)
    }

    private func setIfChanged<V: Equatable>(_ keyPath: ReferenceWritableKeyPath<WindowMenuState, V>, _ newValue: V) {
        if self[keyPath: keyPath] != newValue { self[keyPath: keyPath] = newValue }
    }
}
