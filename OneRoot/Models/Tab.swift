import Foundation
import Observation

/// Which side of a split tab.
enum Pane {
    case primary
    case secondary
}

/// A single tab: one file pane, or two side by side once split (View ▸
/// Split Pane, ⌘\). Each pane's path, history, and sort state live on its
/// own `FileListViewModel` — the sidebar is shared window chrome, not
/// per-tab.
///
/// `fileListViewModel` is whichever pane has focus, so everything that
/// acts on "the current folder" — the sidebar tree, toolbar, address bar,
/// menus, status bar, preview pane — follows the pane you last clicked in
/// without knowing about splits at all. A class (not a struct) so a split
/// tab carries both panes, and its focus, when torn off into another
/// window.
@MainActor
@Observable
final class Tab: Identifiable {
    let id = UUID()
    private(set) var primary: FileListViewModel
    private(set) var secondary: FileListViewModel?
    private(set) var focusedPane: Pane = .primary
    /// Where the folder hierarchy is rooted while this tab is active — set
    /// when a destination is chosen, kept up to date as you browse by
    /// `HierarchyCoordinator`. `nil` until first worked out.
    var hierarchyRoot: HierarchyRoot?
    /// The Inspector tab (Details, More Info, Permissions) last chosen in
    /// this tab.
    var inspectorSection: InspectorSection = .details
    /// The Workspace this tab is working in, while it stays inside one of
    /// its folders — the hierarchy then shows all of them.
    var workspaceID: UUID?
    /// Compare Panes, while it's on (split tabs only).
    private(set) var comparison: PaneComparison?

    init(fileListViewModel: FileListViewModel) {
        primary = fileListViewModel
    }

    /// A tab reopened from a saved session, split or not.
    init(
        primary: FileListViewModel,
        secondary: FileListViewModel?,
        focusedPane: Pane,
        hierarchyRoot: HierarchyRoot? = nil,
        inspectorSection: InspectorSection = .details,
        workspaceID: UUID? = nil
    ) {
        self.inspectorSection = inspectorSection
        self.workspaceID = workspaceID
        self.primary = primary
        self.secondary = secondary
        self.focusedPane = secondary == nil ? .primary : focusedPane
        self.hierarchyRoot = hierarchyRoot
    }

    /// Re-reads both panes from disk (View ▸ Refresh) — for changes the
    /// file watcher didn't report, such as on network shares.
    @discardableResult
    func refresh() -> [Task<Void, Never>] {
        [primary.refresh(), secondary?.refresh()].compactMap { $0 }
    }

    /// The focused pane — see the type's doc comment.
    var fileListViewModel: FileListViewModel {
        focusedPane == .secondary ? (secondary ?? primary) : primary
    }

    var isSplit: Bool { secondary != nil }

    /// The pane that *doesn't* have focus — where Copy/Move to Other Pane
    /// sends things. `nil` unless split.
    var otherPane: FileListViewModel? {
        guard let secondary else { return nil }
        return focusedPane == .secondary ? primary : secondary
    }

    func viewModel(for pane: Pane) -> FileListViewModel? {
        pane == .primary ? primary : secondary
    }

    func focus(_ pane: Pane) {
        guard pane == .primary || secondary != nil, focusedPane != pane else { return }
        focusedPane = pane
    }

    /// Adds a second pane, built by `makePane` and opened at the focused
    /// pane's folder — splitting starts from where you are, like opening a
    /// second Finder window over the same folder. Focus stays put.
    func split(makePane: () -> FileListViewModel) {
        guard secondary == nil else { return }
        let pane = makePane()
        if let url = fileListViewModel.currentLocationURL {
            pane.navigate(to: url)
        }
        secondary = pane
    }

    /// Left becomes right and right becomes left. Focus stays with the
    /// same pane (now on the other side), so you keep working where you were.
    func swapPanes() {
        guard let secondary else { return }
        comparison?.end()
        let focused = fileListViewModel
        self.secondary = primary
        primary = secondary
        focusedPane = focused === primary ? .primary : .secondary
    }

    /// Takes `pane` out of a split tab — it was dragged off into its own
    /// window — leaving this tab single with the other pane. Returns the
    /// removed pane's view model, `nil` if the tab wasn't split.
    func detach(_ pane: Pane) -> FileListViewModel? {
        guard let secondary else { return nil }
        comparison?.end()
        let removed = pane == .primary ? primary : secondary
        primary = pane == .primary ? secondary : primary
        self.secondary = nil
        focusedPane = .primary
        return removed
    }

    /// Back to one pane — the focused one, so closing the split never
    /// yanks you away from the folder you're working in.
    func unsplit() {
        guard let secondary else { return }
        comparison?.end()
        if focusedPane == .secondary {
            primary = secondary
        }
        self.secondary = nil
        focusedPane = .primary
    }

    /// Compares the two panes' folders (or starts over if already
    /// comparing). Does nothing unless split, with both panes in a folder.
    func comparePanes() {
        comparison?.end()
        guard let secondary, let comparison = PaneComparison(left: primary, right: secondary) else { return }
        comparison.onEnd = { [weak self, weak comparison] in
            guard let self, self.comparison === comparison else { return }
            self.comparison = nil
        }
        self.comparison = comparison
        comparison.start()
    }
}
