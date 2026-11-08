import AppKit
import SwiftUI

/// Main-menu commands. Everything they need comes from one stable
/// `@FocusedObject` — `WindowMenuState`, published once by `MainWindowView`
/// via `.focusedSceneObject`. See that type's doc comment for why: the old
/// design published five focused values (two of them fresh closures) and
/// re-applied them on every window `body` pass, which rebuilt the whole menu
/// bar constantly and made every menu flaky.
///
/// A few keyboard shortcuts here duplicate hidden window-scoped buttons in
/// `MainWindowView` (⌘T, ⌘W, ⇧⌘N, …). That's deliberate: AppKit resolves a key
/// window's own view hierarchy before the menu bar, so those keep handling the
/// actual keystroke — this just makes the same actions visible and clickable.

struct FileMenuCommands: Commands {
    @FocusedObject private var menuState: WindowMenuState?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                menuState?.windowViewModel?.openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(menuState?.windowViewModel == nil)

            Button("Duplicate Tab") {
                menuState?.windowViewModel?.duplicateActiveTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(menuState?.fileListViewModel == nil)

            Button("Move Tab to New Window") { moveActiveTabToNewWindow() }
                .keyboardShortcut("t", modifiers: [.command, .control])
                .disabled((menuState?.tabCount ?? 0) < 2)

            Button("Close Tab") {
                guard let windowViewModel = menuState?.windowViewModel else { return }
                guard windowViewModel.tabs.count > 1 || CloseLastTabConfirmation.confirm() else { return }
                windowViewModel.closeActiveTab()
            }
            // Only claim ⌘W while a main window is frontmost. Otherwise this
            // disabled item still shadows AppKit's standard "Close Window",
            // so ⌘W did nothing in the Help / History / Advanced Search
            // windows.
            .keyboardShortcut(menuState?.windowViewModel != nil ? KeyboardShortcut("w", modifiers: .command) : nil)
            .disabled(menuState?.windowViewModel == nil)

            Divider()

            Button("New Folder") { menuState?.fileListViewModel?.promptForNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(menuState?.fileListViewModel == nil)
            Button("New Folder and Open") { menuState?.fileListViewModel?.promptForNewFolderAndOpen() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(menuState?.fileListViewModel == nil)
            Button("New File") { menuState?.fileListViewModel?.promptForNewFile() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(menuState?.fileListViewModel == nil)

            Divider()

            Button("Open") { openSelection(browsePackage: false) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!hasSelection)
            Button("Browse Package Contents") { openSelection(browsePackage: true) }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!hasSelection)
            Button("Quick Look") { menuState?.fileListViewModel?.triggerQuickLook() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(!hasSelection)
            Button("Duplicate") {
                guard let viewModel = menuState?.fileListViewModel else { return }
                viewModel.duplicate(viewModel.selectedNodes)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasSelection || (menuState?.fileListViewModel?.currentDirectory.map(Platform.isTrashFolder) ?? false))

            Divider()

            Button((menuState?.selectionCount ?? 0) > 1 ? "Rename \(menuState?.selectionCount ?? 0) Items\u{2026}" : "Rename") { renameSelection() }
                .disabled(!hasSelection)
            Button("Move to Trash") { moveSelectionToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!hasSelection)
            Menu("Quick Actions") {
                ForEach(menuState?.quickActions ?? []) { option in
                    Button(option.action.menuTitle) {
                        guard let viewModel = menuState?.fileListViewModel else { return }
                        viewModel.promptQuickAction(option.action, for: viewModel.selectedNodes)
                    }
                    .disabled(!option.isAvailable)
                }
            }
            .disabled((menuState?.quickActions ?? []).isEmpty)
            Button("Copy to Other Pane") { menuState?.windowViewModel?.sendSelectionToOtherPane(move: false) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!hasSelection || !(menuState?.isSplit ?? false))
            Button("Move to Other Pane") { menuState?.windowViewModel?.sendSelectionToOtherPane(move: true) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!hasSelection || !(menuState?.isSplit ?? false))
            Button("Eject/Disconnect") { menuState?.ejectActiveRoot() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(!(menuState?.activeRootIsEjectable ?? false))

            Divider()

            Button("Reveal in Finder") { revealSelection() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!hasSelection)
        }
    }

    private var hasSelection: Bool { (menuState?.selectionCount ?? 0) > 0 }

    /// Mirrors `FileTableController.handleOpen` — different layers (AppKit
    /// keyDown / context menu vs. this global menu command), both deferring to
    /// `FileNode.isNavigable(browsePackage:)` for the decision.
    private func openSelection(browsePackage: Bool) {
        guard let fileListViewModel = menuState?.fileListViewModel,
              let node = fileListViewModel.selectedNodes.first else { return }
        if node.isNavigable(browsePackage: browsePackage) {
            fileListViewModel.navigate(to: node.url)
        } else if fileListViewModel.canExtract([node]) {
            fileListViewModel.extractSelection([node])
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    /// The keyboard version of tearing a tab off the tab bar: the same
    /// handoff, a new window opened just down and right of this one.
    private func moveActiveTabToNewWindow() {
        guard let tab = menuState?.windowViewModel?.detachActiveTabForNewWindow() else { return }
        let point = NSApp.keyWindow.map { TabHandoffCenter.cascadePoint(from: $0.frame) } ?? CGPoint(x: 200, y: 700)
        let token = TabHandoffCenter.shared.store(tab, screenPoint: point)
        openWindow(id: OneRootApp.tabHandoffWindowID, value: token)
    }

    /// One item: the usual rename prompt. Several: the batch Rename dialog.
    private func renameSelection() {
        guard let fileListViewModel = menuState?.fileListViewModel else { return }
        let nodes = fileListViewModel.selectedNodes
        if nodes.count == 1 {
            fileListViewModel.promptRename(nodes[0])
        } else if nodes.count > 1 {
            fileListViewModel.promptBatchRename(nodes)
        }
    }

    private func moveSelectionToTrash() {
        guard let fileListViewModel = menuState?.fileListViewModel else { return }
        let nodes = fileListViewModel.selectedNodes
        guard !nodes.isEmpty else { return }
        if TrashConfirmation.confirm(nodes.map(\.name)) {
            fileListViewModel.moveToTrash(nodes)
        }
    }

    private func revealSelection() {
        guard let fileListViewModel = menuState?.fileListViewModel else { return }
        let urls = fileListViewModel.selectedNodes.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// Go menu (Finder has one too): history navigation, the Recent Locations
/// submenu, and Connect to Server.
/// Edit ▸ Deselect All (⌥⌘A, as in Finder), beside the standard Select All.
struct EditMenuCommands: Commands {
    @FocusedObject private var menuState: WindowMenuState?

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            // As in Finder (Copy as Pathname): the selected items' paths, or
            // the current folder's when nothing is selected.
            Button((menuState?.selectionCount ?? 0) > 1 ? "Copy Paths" : "Copy Path") {
                guard let viewModel = menuState?.fileListViewModel else { return }
                if viewModel.selectedNodes.isEmpty {
                    if let folder = viewModel.currentDirectory { viewModel.copyPaths([folder]) }
                } else {
                    viewModel.copyPaths(viewModel.selectedNodes.map(\.url))
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(menuState?.fileListViewModel == nil)
            Button((menuState?.selectionCount ?? 0) > 1 ? "Copy Names" : "Copy Name") {
                guard let viewModel = menuState?.fileListViewModel else { return }
                viewModel.copyNames(viewModel.selectedNodes, includeExtension: true)
            }
            .disabled((menuState?.selectionCount ?? 0) == 0)
            Button((menuState?.selectionCount ?? 0) > 1 ? "Copy Names without Extensions" : "Copy Name without Extension") {
                guard let viewModel = menuState?.fileListViewModel else { return }
                viewModel.copyNames(viewModel.selectedNodes, includeExtension: false)
            }
            .disabled((menuState?.selectionCount ?? 0) == 0)
            Button("Deselect All") { menuState?.fileListViewModel?.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled((menuState?.selectionCount ?? 0) == 0)
        }
    }
}

struct GoMenuCommands: Commands {
    @FocusedObject private var menuState: WindowMenuState?
    @Environment(\.openWindow) private var openWindow

    /// How many recent locations the submenu shows. The full list (up to the
    /// user's configured cap) lives in the History window; a menu is the wrong
    /// place for 50–200 rows.
    private static let submenuLimit = 12

    var body: some Commands {
        CommandMenu("Go") {
            Button("Back") { menuState?.fileListViewModel?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(menuState?.canGoBack ?? false))
            Button("Forward") { menuState?.fileListViewModel?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(menuState?.canGoForward ?? false))
            Button("Up One Level") { menuState?.fileListViewModel?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!(menuState?.canGoUp ?? false))
            Button("Go to Folder\u{2026}") { menuState?.fileListViewModel?.beginEditingAddress() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(menuState?.fileListViewModel == nil)

            Divider()

            Menu("Recent Locations") {
                ForEach(recentLocations.prefix(Self.submenuLimit), id: \.self) { url in
                    Button(Self.menuTitle(for: url)) { menuState?.fileListViewModel?.navigate(to: url) }
                        .disabled(menuState?.fileListViewModel == nil)
                }
                if recentLocations.isEmpty {
                    Button("No Recent Locations") {}
                        .disabled(true)
                }

                Divider()

                // Enabled regardless of which window is frontmost, so ⌥⌘Y
                // opens the History window from anywhere (it just shows
                // "No history yet" when empty). The submenu itself is *not*
                // disabled as a whole — only the navigate rows above are —
                // so this stays reachable.
                Button("Show All History…") { openWindow(id: OneRootApp.historyWindowID) }
                    .keyboardShortcut("y", modifiers: [.command, .option])
                Button("Clear Menu") { NavigationHistoryStore.shared.clear() }
                    .disabled(recentLocations.isEmpty)
            }

            Divider()

            Button("Connect to Server…") { menuState?.requestConnectToServer() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(menuState == nil)
        }
    }

    private var recentLocations: [URL] { menuState?.recentLocations ?? [] }

    /// Folder name for the row, falling back to the full path for a volume
    /// root (`/`, `/Volumes/Foo`) where the last component isn't meaningful.
    private static func menuTitle(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? url.path : name
    }
}

/// View menu: tabs, hidden files, sidebar tree expansion, Advanced Search.
struct ViewMenuCommands: Commands {
    @FocusedObject private var menuState: WindowMenuState?
    @Environment(\.openWindow) private var openWindow
    private var folderSizePreferences = FolderSizePreferenceStore.shared

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            // Tabs — also on each tab's right-click menu.
            Button("Show Next Tab") { menuState?.windowViewModel?.selectAdjacentTab(1) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((menuState?.tabCount ?? 0) < 2)
            Button("Show Previous Tab") { menuState?.windowViewModel?.selectAdjacentTab(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((menuState?.tabCount ?? 0) < 2)
            Button("Close Other Tabs") {
                guard let windowViewModel = menuState?.windowViewModel, let tab = windowViewModel.activeTab else { return }
                windowViewModel.closeOtherTabs(keeping: tab)
            }
            // Not ⌥⌘W: that's macOS's own Close All, which wins and closes
            // the window.
            .keyboardShortcut("w", modifiers: [.command, .control])
            .disabled((menuState?.tabCount ?? 0) < 2)
            Button("Close Tabs to the Right") {
                guard let windowViewModel = menuState?.windowViewModel, let tab = windowViewModel.activeTab else { return }
                windowViewModel.closeTabsToTheRight(of: tab)
            }
            .keyboardShortcut("w", modifiers: [.command, .option, .control])
            .disabled(menuState?.activeTabIsLast ?? true)

            Divider()

            Toggle("as Icons", isOn: viewModeBinding(.icons))
                .keyboardShortcut("1", modifiers: .command)
                .disabled(menuState?.fileListViewModel == nil)
            Toggle("as List", isOn: viewModeBinding(.list))
                .keyboardShortcut("2", modifiers: .command)
                .disabled(menuState?.fileListViewModel == nil)

            Divider()

            Toggle("Dual Pane", isOn: Binding(
                get: { menuState?.isSplit ?? false },
                set: { _ in menuState?.windowViewModel?.toggleSplitActiveTab() }
            ))
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(menuState?.windowViewModel == nil)
            Button("Swap Panes") { menuState?.windowViewModel?.activeTab?.swapPanes() }
                .keyboardShortcut("\\", modifiers: [.command, .option])
                .disabled(!(menuState?.isSplit ?? false))
            Button("Compare Panes") { menuState?.windowViewModel?.activeTab?.comparePanes() }
                .disabled(!(menuState?.isSplit ?? false))
            Button("Refresh") {
                menuState?.windowViewModel?.activeTab?.refresh()
                menuState?.hierarchyViewModel?.requestRefreshAll()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(menuState?.windowViewModel == nil)
            // A one-off for the current view — the automatic version is
            // Settings ▸ General ▸ Always calculate folder sizes.
            Button("Calculate Folder Sizes") { menuState?.fileListViewModel?.calculateFolderSizesInView() }
                .disabled(menuState?.fileListViewModel == nil || folderSizePreferences.calculateAll)

            Button((menuState?.showHiddenFiles ?? false) ? "Hide Hidden Files" : "Show Hidden Files") {
                menuState?.fileListViewModel?.toggleShowHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(menuState?.fileListViewModel == nil)
            Toggle("Show All Files in Subfolders", isOn: Binding(
                get: { menuState?.showsAllFilesInSubfolders ?? false },
                set: { menuState?.fileListViewModel?.setShowsAllFilesInSubfolders($0) }
            ))
            .disabled(menuState?.fileListViewModel?.currentDirectory == nil)

            Divider()

            Toggle("Destinations", isOn: layoutBinding(\.showsDestinations, shown: menuState?.showsDestinations))
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(menuState?.windowViewModel == nil)
            Toggle("Folder Hierarchy", isOn: layoutBinding(\.showsHierarchy, shown: menuState?.showsHierarchy))
                .keyboardShortcut("h", modifiers: [.command, .control])
                .disabled(menuState?.windowViewModel == nil)
            Toggle("Inspector", isOn: layoutBinding(\.showsInspector, shown: menuState?.showsInspector))
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(menuState?.windowViewModel == nil)
            Toggle("Tools Panel", isOn: Binding(
                get: { menuState?.isWorkspaceExpanded ?? false },
                set: { menuState?.windowViewModel?.setWorkspaceExpanded($0) }
            ))
            .keyboardShortcut("b", modifiers: [.command, .control])
            .disabled(menuState?.windowViewModel == nil)
            Button("Reset Window Layout") { menuState?.windowViewModel?.layout.reset() }
                .disabled(menuState?.windowViewModel == nil)

            Divider()

            Button("Collapse All Folders") { menuState?.hierarchyViewModel?.requestCollapseAll() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(menuState?.hierarchyViewModel == nil)
            Button("Expand Top Level") { menuState?.hierarchyViewModel?.requestExpandTopLevel() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(menuState?.hierarchyViewModel == nil)

            Divider()

            Button("Advanced Search…") { openWindow(id: OneRootApp.advancedSearchWindowID) }
                .keyboardShortcut("/", modifiers: [.command, .option])
            Button("Find Duplicates…") {
                // The current folder — and with Dual Pane on, the other one too.
                guard let tab = menuState?.windowViewModel?.activeTab else { return }
                let roots = [tab.primary, tab.secondary].compactMap { $0?.currentDirectory }
                guard !roots.isEmpty else { return }
                DuplicatesHandoffCenter.shared.hand(Array(NSOrderedSet(array: roots)) as? [URL] ?? roots)
                openWindow(id: OneRootApp.duplicatesWindowID)
            }
            .disabled(menuState?.fileListViewModel?.currentDirectory == nil)
            Button("Search Subfolders with This Filter") {
                guard let criteria = menuState?.fileListViewModel?.filterAsSubfolderSearch() else { return }
                SearchHandoffCenter.shared.hand(criteria)
                openWindow(id: OneRootApp.advancedSearchWindowID)
            }
            .disabled(!(menuState?.hasFilter ?? false))
            Button("Clear Filters") { menuState?.fileListViewModel?.clearFilter() }
                .disabled(!(menuState?.hasFilter ?? false))
        }
    }

    /// A pane's View-menu checkbox: shows the mirrored value (never reads the
    /// live layout, so menus only re-render when it really changes — see
    /// `WindowMenuState`), and toggles the window's layout.
    private func layoutBinding(_ keyPath: WritableKeyPath<WindowLayout, Bool>, shown: Bool?) -> Binding<Bool> {
        Binding(
            get: { shown ?? false },
            set: { menuState?.windowViewModel?.layout.set(keyPath, $0) }
        )
    }

    /// Checked for the active tab's current mode; choosing it switches the
    /// current folder (and remembers that for the folder).
    private func viewModeBinding(_ mode: FileViewMode) -> Binding<Bool> {
        Binding(
            get: { menuState?.viewMode == mode },
            set: { _ in menuState?.fileListViewModel?.setViewMode(mode) }
        )
    }
}

/// Replaces the default Help menu: the in-app Help window (and its Coming
/// from Windows topic directly) plus the ⌘B keyboard-shortcuts quick popover.
struct HelpMenuCommands: Commands {
    @FocusedObject private var menuState: WindowMenuState?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { menuState?.requestShortcutsQuickView() }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(menuState == nil)
            Button("\(AppConfig.displayName) Help") { openWindow(id: OneRootApp.helpWindowID) }
                .keyboardShortcut("?", modifiers: .command)
            Button("Coming from Windows") {
                HelpNavigator.shared.request(.comingFromWindows)
                openWindow(id: OneRootApp.helpWindowID)
            }
        }
    }
}
