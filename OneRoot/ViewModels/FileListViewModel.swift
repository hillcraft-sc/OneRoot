import Foundation
import Observation

enum SortDirection {
    case ascending, descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

/// Items a Replace sent to the Trash get their origin recorded, so the
/// Trash view's Put Back knows where they came from. Shared by
/// `FileListViewModel` and `FolderHierarchyViewModel`.
@MainActor
func recordReplacedItemOrigins(_ changes: [FileChange], trashOriginService: TrashOriginService) {
    for case .trashed(let original, let trashedAt) in changes {
        trashOriginService.recordOrigin(trashedURL: trashedAt, originalURL: original)
    }
}

/// What a pending "New Folder" name prompt will do once a name is chosen.
enum NewFolderIntent {
    /// Plain ⇧⌘N / context-menu "New Folder" — create in the current
    /// directory; `andOpen` distinguishes "New Folder and Open" (⌘⌥N).
    case inCurrentDirectory(andOpen: Bool)
    /// "New Folder Here" from right-clicking a specific folder — create
    /// inside it regardless of what directory the list is currently
    /// showing, then always navigate into the new folder.
    case inside(FileNode)
}

@MainActor
@Observable
final class FileListViewModel {
    private(set) var items: [FileNode] = []
    private(set) var currentDirectory: URL?
    /// Recents or Shared, while one is shown instead of a folder
    /// (`currentDirectory` is then `nil`).
    private(set) var virtualLocation: VirtualLocation?
    private(set) var errorMessage: String?
    /// Why the current folder couldn't be listed, if it couldn't — unlike
    /// `errorMessage`, never a failed file operation.
    private(set) var listingErrorMessage: String?
    /// The folder couldn't be read for lack of permission — the file list
    /// offers the Full Disk Access settings instead of just the error.
    private(set) var isPermissionDenied = false
    /// A navigation's listing is still on its way. Not set for passive
    /// refreshes (FSEvents, after a file operation), which keep showing
    /// the current contents meanwhile.
    private(set) var isLoading = false
    private(set) var sortField: FileColumn = .name
    private(set) var sortDirection: SortDirection = .ascending
    private(set) var groupBy: FileColumn?
    private(set) var visibleColumns: [FileColumn]
    /// The table's current selection, last reported by `FileTableController`
    /// via `onSelectionChange`. `FileTableController` remains the source of
    /// truth for its own selection state; this is just a cached mirror so
    /// SwiftUI views outside the table (the shortcut toolbar) can react to
    /// "what's selected" without owning it themselves.
    private(set) var selectedNodes: [FileNode] = []
    /// Set by the Return key, "Rename" context-menu item, or the shortcut
    /// toolbar's Rename button; `FileListView` shows the rename alert
    /// whenever this is non-nil.
    var pendingRenameNode: FileNode?
    /// Set when several items are renamed at once; `FileListView` shows the
    /// batch Rename dialog (`BatchRenameView`) while this is non-nil.
    var pendingBatchRenameNodes: [FileNode]?
    /// Set by Quick Actions ▾ / the context menu; `FileListView` shows that
    /// action's sheet (`QuickActionSheet`) while this is non-nil.
    var pendingQuickAction: PendingQuickAction?
    private(set) var showHiddenFiles: Bool
    /// Flat view (#66): every file in this folder and its subfolders, in
    /// one list. Off again when you go to another folder.
    private(set) var showsAllFilesInSubfolders = false
    /// The flat view stopped at `FileSystemService.flatViewLimit` files.
    private(set) var flatViewIsTruncated = false
    private var flatGeneration = 0

    /// Compare Panes: each item's status against the other pane, by name
    /// (`PaneComparison` sets it). `nil` when not comparing.
    var comparisonStatuses: [String: ComparisonStatus]?
    /// Compare Panes' Differences Only: the names to keep showing. `nil`
    /// shows everything.
    var comparisonFilter: Set<String>? {
        didSet {
            guard comparisonFilter != oldValue else { return }
            items = filteredAndSorted(unsortedItems)
        }
    }
    /// Name collisions a copy/move is waiting on; `FileListView` asks
    /// about them (see `FileConflictPrompt`).
    private(set) var pendingConflicts: FileConflictRequest?
    /// What's typed in the search field: `filter`'s name pattern.
    var searchText: String = "" {
        didSet { if filter.pattern != searchText { filter.pattern = searchText } }
    }
    /// The list's filter — the name typed in the search field plus any
    /// chips added (Kind, Modified, Size, …). Stays on from folder to folder
    /// until cleared, so you can look for the same thing in the next one.
    /// The same model Advanced Search uses, so Search Subfolders carries it
    /// over as is. Its `root` isn't used here.
    var filter = SearchCriteria(root: URL(fileURLWithPath: "/")) {
        didSet {
            if searchText != filter.pattern { searchText = filter.pattern }
            items = filteredAndSorted(unsortedItems)
        }
    }
    /// Why the filter can't be applied (an unfinished regex), shown on its
    /// Name chip; nothing is listed meanwhile.
    private(set) var filterError: String?
    /// Bumped by `focusSearchField()` (the window's `/` shortcut);
    /// `SearchFieldView` observes it to move keyboard focus into its
    /// `TextField`. A counter rather than a `Bool` so pressing `/` again
    /// while the field is already focused still fires `onChange`.
    private(set) var searchFieldFocusTrigger = 0
    /// Bumped by Go ▸ Go to Folder… (⇧⌘G); `AddressBarView` switches from
    /// breadcrumbs to its text field. A counter for the same reason.
    private(set) var addressEditTrigger = 0
    /// List or icons — follows each folder's remembered choice as you
    /// navigate (see `FolderViewModeService`).
    private(set) var viewMode: FileViewMode = .list
    /// Recursive sizes of folders in this folder, for the Size column —
    /// filled in automatically (Settings ▸ Always calculate folder sizes), for
    /// the whole view (View ▸ Calculate Folder Sizes), or per folder by
    /// the context menu's Calculate Size. See `FolderSizeService`.
    private(set) var folderSizes: [URL: Int64] = [:]
    /// Folders whose size is being worked out right now ("Calculating…").
    private(set) var calculatingFolderSizes: Set<URL> = []
    /// Set by any of the "New Folder…" triggers; `FileListView` shows a
    /// name prompt whenever this is non-nil and clears it once the user
    /// picks a name or cancels.
    var pendingNewFolderIntent: NewFolderIntent?
    /// Set by ⌘F or the context menu's "New File"; `FileListView` shows a
    /// name prompt whenever this is `true` and clears it once the user
    /// picks a name or cancels. Always creates in the current directory —
    /// unlike folders, there's no "New File Here"/"and Open" variant.
    var pendingNewFileIntent = false
    /// Set while `restore(_:)` is waiting on the user to pick a folder for
    /// an item OneRoot doesn't know the original location of;
    /// `FileListView` shows `FileChooserView` whenever this is non-nil.
    private(set) var pendingRestoreDestinationItemName: String?
    /// Set while `compressSelection(_:)` is waiting on the user to pick a
    /// destination (only happens when Settings > Archives is set to "Ask
    /// Every Time"); `FileListView` shows `FileChooserView` whenever this
    /// is non-nil.
    private(set) var pendingArchiveDestinationItemName: String?
    /// Set while `extractSelection(_:)` is waiting on a destination —
    /// unlike compressing, extracting always asks, so this has no
    /// Settings-driven bypass.
    private(set) var pendingExtractDestinationItemName: String?
    /// Non-nil while a compress/extract subprocess is actually running (not
    /// while just waiting on a destination-picker sheet) — `StatusBarView`
    /// shows this with a spinner so a large folder taking a while doesn't
    /// look like nothing is happening.
    private(set) var archiveOperationStatus: String?
    /// Set right after a successful compress to the archive's destination
    /// folder — `FileListView` observes this and calls the window's own
    /// "open in new tab" path, then clears it.
    private(set) var pendingOpenInNewTabDirectory: URL?
    /// Bumped by the main menu's ⌘Y "Quick Look" command; `FileTableController`
    /// (via `FileTableRepresentable.updateNSView`) observes this and toggles
    /// the Quick Look panel — a counter, like `searchFieldFocusTrigger`, so
    /// choosing the menu item again while the panel's already open still
    /// fires a change.
    private(set) var quickLookTrigger = 0
    /// Bumped to clear the file view's selection (the "✕" on the command
    /// bar's selection strip) — the selection itself lives in AppKit.
    private(set) var clearSelectionTrigger = 0
    /// Bumped (with `requestedSelection`) when something outside the list
    /// asks for items to be selected — Visualize revealing a file.
    private(set) var selectionRequest = 0
    private(set) var requestedSelection: Set<URL> = []

    private let fileSystemService: FileSystemService
    private let tagService = TagService()
    private let fileWatcher: FileWatching
    private let trashOriginService: TrashOriginService
    private let columnPreferences: ColumnPreferencesStore
    private let hiddenFilesPreferences: HiddenFilesPreferenceStore
    private let navigationHistory: NavigationHistoryStore
    private let archiveService: ArchiveService
    private let archiveSettings: ArchiveSettingsService
    let undoCenter: FileUndoCenter
    private let clipboard: FileClipboard
    private let virtualListing: VirtualListing
    /// The folder sort, put back on leaving Recents (which sorts by when
    /// things were opened).
    @ObservationIgnored private var sortBeforeRecents: (field: FileColumn, direction: SortDirection)?
    private let folderViewModes: FolderViewModeService
    private var unsortedItems: [FileNode] = []
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    @ObservationIgnored private var columnsWatch: ObservationWatch?
    @ObservationIgnored private var hiddenFilesWatch: ObservationWatch?
    private let folderSizeService: FolderSizeService
    private let folderSizeCache: FolderSizeCache
    private let folderSizePreferences: FolderSizePreferenceStore
    @ObservationIgnored private var folderSizePreferenceWatch: ObservationWatch?
    @ObservationIgnored private var datesChangedObserver: NotificationObservers?
    /// Folders to size next, in order; worked through by `folderSizeWorker`.
    @ObservationIgnored private var pendingFolderSizes: [URL] = []
    @ObservationIgnored private var folderSizeWorker: Task<Void, Never>?
    /// Bumped on navigation, so a cancelled worker finishing late can't
    /// clear the next folder's worker.
    @ObservationIgnored private var folderSizeGeneration = 0
    /// Folders sized by hand (context menu) — kept up to date after changes
    /// even while Calculate All is off.
    @ObservationIgnored private var requestedFolderSizes: Set<URL> = []
    private let conflictQueue = FileConflictQueue()
    @ObservationIgnored private var restoreDestinationContinuation: CheckedContinuation<URL?, Never>?
    @ObservationIgnored private var archiveDestinationContinuation: CheckedContinuation<URL?, Never>?
    @ObservationIgnored private var extractDestinationContinuation: CheckedContinuation<URL?, Never>?

    /// Folders Back would reach, nearest first (the Back button's history menu).
    var backHistory: [URL] { Array(backStack.reversed()) }
    /// Folders Forward would reach, nearest first.
    var forwardHistory: [URL] { Array(forwardStack.reversed()) }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    /// What's shown, as history records it: the folder, or Recents/Shared's
    /// own `oneroot:` URL.
    var currentLocationURL: URL? { currentDirectory ?? virtualLocation?.url }
    var canGoUp: Bool {
        guard let current = currentDirectory else { return false }
        return current.deletingLastPathComponent().path != current.path
    }
    var canPaste: Bool {
        clipboard.hasFiles
    }

    /// `fileWatcher` defaults to inert rather than watching real machine
    /// state, so tests stay hermetic and don't each start a real FSEvents
    /// stream; the production call site (`WindowViewModel`) injects a real
    /// `FileWatcher` explicitly.
    /// `columnPreferences` defaults to `nil` rather than `.shared` directly
    /// — a default *parameter value* isn't considered part of this
    /// `@MainActor` initializer for isolation-checking purposes, so
    /// referencing the `@MainActor`-isolated `.shared` there doesn't
    /// compile under Swift 6 language mode. Resolving it in the body
    /// (which *is* actor-isolated) sidesteps that.
    init(
        fileSystemService: FileSystemService = FileSystemService(),
        fileWatcher: FileWatching = NullFileWatcher(),
        trashOriginService: TrashOriginService = TrashOriginService(),
        columnPreferences: ColumnPreferencesStore? = nil,
        hiddenFilesPreferences: HiddenFilesPreferenceStore? = nil,
        navigationHistory: NavigationHistoryStore? = nil,
        archiveService: ArchiveService = ArchiveService(),
        archiveSettings: ArchiveSettingsService = ArchiveSettingsService(),
        undoCenter: FileUndoCenter? = nil,
        clipboard: FileClipboard? = nil,
        folderViewModes: FolderViewModeService = FolderViewModeService(),
        folderSizeService: FolderSizeService = FolderSizeService(),
        folderSizeCache: FolderSizeCache? = nil,
        folderSizePreferences: FolderSizePreferenceStore? = nil,
        virtualListing: VirtualListing = VirtualListingService()
    ) {
        self.virtualListing = virtualListing
        self.folderViewModes = folderViewModes
        self.folderSizeService = folderSizeService
        self.folderSizeCache = folderSizeCache ?? .shared
        self.folderSizePreferences = folderSizePreferences ?? .shared
        let columnPreferences = columnPreferences ?? .shared
        self.undoCenter = undoCenter ?? .shared
        self.clipboard = clipboard ?? Platform.clipboard
        let hiddenFilesPreferences = hiddenFilesPreferences ?? .shared
        let navigationHistory = navigationHistory ?? .shared
        self.fileSystemService = fileSystemService
        self.fileWatcher = fileWatcher
        self.trashOriginService = trashOriginService
        self.columnPreferences = columnPreferences
        self.hiddenFilesPreferences = hiddenFilesPreferences
        self.navigationHistory = navigationHistory
        self.archiveService = archiveService
        self.archiveSettings = archiveSettings
        self.visibleColumns = columnPreferences.visibleColumns
        self.showHiddenFiles = hiddenFilesPreferences.showHiddenFiles
        fileWatcher.onChange = { [weak self] in
            guard let self else { return }
            self.folderContentsChanged(self.fileWatcher.drainChangedPaths())
            self.refresh()
        }
        columnsWatch = ObservationWatch.watch({ columnPreferences.visibleColumns }, emitsInitialValue: false) { [weak self] in
            self?.setVisibleColumns($0)
        }
        // Unlike columns, a hidden-files change needs a fresh fetch from
        // disk (hidden entries were never fetched at all while the
        // preference was off) — a plain re-filter of `unsortedItems`
        // wouldn't have them to show. The equality guard skips a change
        // that ends up where it started.
        hiddenFilesWatch = ObservationWatch.watch({ hiddenFilesPreferences.showHiddenFiles }, emitsInitialValue: false) { [weak self] newValue in
            guard let self, self.showHiddenFiles != newValue else { return }
            self.showHiddenFiles = newValue
            self.refresh()
        }
        datesChangedObserver = NotificationObservers([
            NotificationCenter.default.addObserver(forName: .fileListDatesChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.refresh() }
            },
        ])
        let folderSizePreferences = self.folderSizePreferences
        folderSizePreferenceWatch = ObservationWatch.watch({ folderSizePreferences.calculateAll }, emitsInitialValue: false) { [weak self] calculateAll in
            self?.calculateAllFolderSizesChanged(calculateAll)
        }
    }

    // MARK: Columns

    /// Whether the list shows, sorts, or groups by Date Last Opened — the
    /// only time Spotlight's dates are worth looking up.
    var needsLastOpenedDates: Bool {
        displayedColumns.contains(.dateLastOpened) || sortField == .dateLastOpened || groupBy == .dateLastOpened
    }

    /// Re-reads the folder when Date Last Opened has just become needed,
    /// so its Spotlight dates fill in.
    private func reloadIfLastOpenedBecameNeeded(_ wasNeeded: Bool) {
        if !wasNeeded, needsLastOpenedDates, currentDirectory != nil, !showsAllFilesInSubfolders { refresh() }
    }

    private func setVisibleColumns(_ columns: [FileColumn]) {
        let wasNeeded = needsLastOpenedDates
        visibleColumns = columns
        reloadIfLastOpenedBecameNeeded(wasNeeded)
    }

    func toggleColumn(_ column: FileColumn) {
        columnPreferences.toggle(column)
    }

    func reorderColumns(_ columns: [FileColumn]) {
        // Where shown only because this is Recents/Shared isn't saved as
        // a column you chose.
        let chosen = visibleColumns.contains(.location) ? columns : columns.filter { $0 != .location }
        columnPreferences.setOrder(chosen)
    }

    func toggleShowHiddenFiles() {
        hiddenFilesPreferences.toggle()
    }

    // MARK: Navigation

    /// Navigates to `url`. By default this is a "new" navigation: it's
    /// pushed onto the back stack and clears any forward history, matching
    /// how a browser/Explorer address bar behaves. Returns the underlying
    /// load `Task` so tests can await completion; UI call sites ignore it.
    @discardableResult
    func navigate(to url: URL, recordHistory: Bool = true) -> Task<Void, Never> {
        if let location = VirtualLocation(url: url) {
            return show(location, recordHistory: recordHistory)
        }
        if recordHistory, let current = currentLocationURL, current != url {
            backStack.append(current)
            forwardStack.removeAll()
        }
        leaveVirtualLocation()
        if currentDirectory != url {
            resetFolderSizes()
            // Nothing in the new folder is selected yet.
            if !selectedNodes.isEmpty { selectedNodes = [] }
        }
        if currentDirectory != url, showsAllFilesInSubfolders {
            showsAllFilesInSubfolders = false
            flatViewIsTruncated = false
        }
        currentDirectory = url
        // Before the listing loads, so the folder never flashes up in the
        // previous folder's view first.
        viewMode = folderViewModes.mode(for: url)
        errorMessage = nil
        listingErrorMessage = nil
        isPermissionDenied = false
        isLoading = true
        fileWatcher.watch([url])
        return load(url, recordInHistory: true)
    }

    /// Reloads the current directory in place — no history change, no
    /// watcher restart. Used for FSEvents-triggered live refresh and after
    /// file operations complete.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        if let virtualLocation { return loadVirtual(virtualLocation) }
        guard let url = currentDirectory else { return nil }
        return load(url, recordInHistory: false)
    }

    // MARK: Recents and Shared

    /// Shows Recents or Shared in place of a folder. Recorded in history
    /// like a folder; nothing is watched (refresh reloads it).
    @discardableResult
    private func show(_ location: VirtualLocation, recordHistory: Bool) -> Task<Void, Never> {
        if recordHistory, let current = currentLocationURL, current != location.url {
            backStack.append(current)
            forwardStack.removeAll()
        }
        if virtualLocation != location {
            resetFolderSizes()
            if !selectedNodes.isEmpty { selectedNodes = [] }
        }
        // Recents always opens newest first, by when things were opened.
        if location == .recents {
            if sortBeforeRecents == nil { sortBeforeRecents = (sortField, sortDirection) }
            sortField = .dateLastOpened
            sortDirection = .descending
        } else {
            restoreSortAfterRecents()
        }
        currentDirectory = nil
        virtualLocation = location
        viewMode = .list
        errorMessage = nil
        listingErrorMessage = nil
        isPermissionDenied = false
        isLoading = true
        unsortedItems = []
        items = []
        fileWatcher.watch([])
        return loadVirtual(location)
    }

    private func loadVirtual(_ location: VirtualLocation) -> Task<Void, Never> {
        let listing = virtualListing
        return Task {
            do {
                let nodes = try await Task.detached(priority: .userInitiated) {
                    try await listing.items(for: location)
                }.value
                guard virtualLocation == location else { return }
                isLoading = false
                unsortedItems = nodes
                items = filteredAndSorted(nodes)
                refreshSelectedNodes(from: nodes)
            } catch is CancellationError {
                // Superseded.
            } catch {
                guard virtualLocation == location else { return }
                isLoading = false
                listingErrorMessage = error.localizedDescription
            }
        }
    }

    private func leaveVirtualLocation() {
        guard virtualLocation != nil else { return }
        virtualLocation = nil
        restoreSortAfterRecents()
    }

    private func restoreSortAfterRecents() {
        guard let saved = sortBeforeRecents else { return }
        sortBeforeRecents = nil
        sortField = saved.field
        sortDirection = saved.direction
    }

    /// The columns to show: in Recents and Shared, Where is always there,
    /// right after the name — the items come from all over.
    var displayedColumns: [FileColumn] {
        guard virtualLocation != nil || showsAllFilesInSubfolders, !visibleColumns.contains(.location) else { return visibleColumns }
        return [.name, .location] + visibleColumns.filter { $0 != .name }
    }

    /// `recordInHistory` is true only for an actual `navigate(to:)` — never
    /// for an FSEvents live refresh or a post-file-op reload. Passive
    /// reloads of the folder you're already sitting in aren't "visits", and
    /// letting them publish into `NavigationHistoryStore` on every
    /// filesystem tick made the Go menu's Recent Locations submenu flicker
    /// and dismiss while it was open.
    /// Turns the flat view on or off for the current folder.
    @discardableResult
    func setShowsAllFilesInSubfolders(_ isOn: Bool) -> Task<Void, Never>? {
        guard let url = currentDirectory, isOn != showsAllFilesInSubfolders else { return nil }
        showsAllFilesInSubfolders = isOn
        flatViewIsTruncated = false
        if !selectedNodes.isEmpty { selectedNodes = [] }
        isLoading = true
        unsortedItems = []
        items = []
        return load(url, recordInHistory: false)
    }

    /// Fills the list with every file under `url`, batch by batch.
    private func loadAllFiles(_ url: URL) -> Task<Void, Never> {
        flatGeneration += 1
        let generation = flatGeneration
        let service = fileSystemService
        let includeHidden = showHiddenFiles
        // Fill in as it goes only when starting from empty; a refresh swaps
        // the whole list at the end instead of shrinking it meanwhile.
        let progressive = unsortedItems.isEmpty
        return Task {
            var collected: [FileNode] = []
            do {
                let truncated = try await service.listAllFiles(under: url, includeHidden: includeHidden) { batch in
                    await MainActor.run {
                        guard self.flatGeneration == generation, self.currentDirectory == url, self.showsAllFilesInSubfolders else { return }
                        collected.append(contentsOf: batch)
                        guard progressive else { return }
                        self.unsortedItems = collected
                        self.items = self.filteredAndSorted(collected)
                    }
                }
                guard flatGeneration == generation, currentDirectory == url, showsAllFilesInSubfolders else { return }
                isLoading = false
                flatViewIsTruncated = truncated
                unsortedItems = collected
                items = filteredAndSorted(collected)
                refreshSelectedNodes(from: collected)
            } catch {
                guard flatGeneration == generation, currentDirectory == url else { return }
                isLoading = false
            }
        }
    }

    @discardableResult
    private func load(_ url: URL, recordInHistory: Bool) -> Task<Void, Never> {
        if showsAllFilesInSubfolders { return loadAllFiles(url) }
        return Task {
            do {
                let nodes = try await fileSystemService.listDirectory(url, includeHidden: showHiddenFiles, wantsLastOpenedDates: needsLastOpenedDates)
                guard currentDirectory == url else { return } // superseded by a newer navigation
                isLoading = false
                if listingErrorMessage != nil {
                    // A refresh read it fine after all (permission granted).
                    listingErrorMessage = nil
                    isPermissionDenied = false
                }
                unsortedItems = nodes
                if recordInHistory {
                    showCachedFolderSizes()
                }
                items = filteredAndSorted(nodes)
                refreshSelectedNodes(from: nodes)
                queueMissingFolderSizes(revalidateAll: recordInHistory)
                // Only folders that actually listed make it into the
                // app-wide browsing history — a mistyped address-bar path
                // or a vanished share never gets recorded.
                if recordInHistory { navigationHistory.record(url) }
            } catch {
                guard currentDirectory == url else { return } // superseded by a newer navigation
                isLoading = false
                unsortedItems = []
                items = []
                // The address bar already rejects paths that don't exist at
                // the moment of navigation (see `PathResolver`), so reaching
                // this with a "no such file" error means the directory
                // disappeared out from under an already-open tab — a
                // network share disconnecting, a USB drive being ejected, or
                // a delete. Staying put would just leave the tab stuck
                // showing a dead path and a permanent error banner, so it
                // goes to the nearest folder above that's still there (which
                // keeps a Workspace or split pane where it was), or home.
                if isMissingDirectoryError(error) {
                    let fallback = await fileSystemService.nearestExistingFolder(above: url) ?? Self.homeURL
                    guard currentDirectory == url else { return }
                    navigate(to: fallback, recordHistory: false)
                } else {
                    errorMessage = error.localizedDescription
                    listingErrorMessage = error.localizedDescription
                    isPermissionDenied = isPermissionError(error)
                }
            }
        }
    }

    private static let homeURL = FileManager.default.homeDirectoryForCurrentUser

    private func isPermissionError(_ error: Error) -> Bool {
        guard case FileSystemError.cannotList(_, let underlying) = error else { return false }
        let nsError = underlying as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError { return true }
        let posix = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError) ?? nsError
        return posix.domain == NSPOSIXErrorDomain && (posix.code == Int(EACCES) || posix.code == Int(EPERM))
    }

    private func isMissingDirectoryError(_ error: Error) -> Bool {
        guard case FileSystemError.cannotList(_, let underlying) = error else { return false }
        let nsError = underlying as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
    }

    /// Back `steps` entries (1 is the previous folder). The folders passed on
    /// the way, and this one, become forward history in order, so choosing an
    /// entry from the Back list steps through history instead of adding to it.
    @discardableResult
    func goBack(steps: Int = 1) -> Task<Void, Never>? {
        guard steps >= 1, steps <= backStack.count else { return nil }
        var passed = currentLocationURL.map { [$0] } ?? []
        var target: URL?
        for _ in 0..<steps {
            if let target { passed.append(target) }
            target = backStack.popLast()
        }
        guard let target else { return nil }
        forwardStack.append(contentsOf: passed)
        return navigate(to: target, recordHistory: false)
    }

    @discardableResult
    func goForward(steps: Int = 1) -> Task<Void, Never>? {
        guard steps >= 1, steps <= forwardStack.count else { return nil }
        var passed = currentLocationURL.map { [$0] } ?? []
        var target: URL?
        for _ in 0..<steps {
            if let target { passed.append(target) }
            target = forwardStack.popLast()
        }
        guard let target else { return nil }
        backStack.append(contentsOf: passed)
        return navigate(to: target, recordHistory: false)
    }

    @discardableResult
    func goUp() -> Task<Void, Never>? {
        guard let current = currentDirectory else { return nil }
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else { return nil }
        return navigate(to: parent)
    }

    // MARK: Sorting

    /// Puts back a sort saved with the session — unlike `setSort`, sets the
    /// direction outright rather than toggling it.
    func restoreSort(field: FileColumn, ascending: Bool) {
        sortField = field
        sortDirection = ascending ? .ascending : .descending
        items = filteredAndSorted(unsortedItems)
    }

    func setSort(field: FileColumn) {
        let wasNeeded = needsLastOpenedDates
        defer { reloadIfLastOpenedBecameNeeded(wasNeeded) }
        if sortField == field {
            sortDirection.toggle()
        } else {
            sortField = field
            sortDirection = .ascending
        }
        items = filteredAndSorted(unsortedItems)
    }

    /// `nil` turns grouping off. Group order itself always runs ascending
    /// (Today before Yesterday, Folders before files, etc.) regardless of
    /// `sortDirection` — only the ordering *within* a group follows the
    /// current sort field/direction, matching Finder's "Arrange By".
    func setGroupBy(_ field: FileColumn?) {
        let wasNeeded = needsLastOpenedDates
        defer { reloadIfLastOpenedBecameNeeded(wasNeeded) }
        groupBy = field
        items = filteredAndSorted(unsortedItems)
    }

    private func filteredAndSorted(_ nodes: [FileNode]) -> [FileNode] {
        let nodes = comparisonFilter.map { keep in nodes.filter { keep.contains($0.name) } } ?? nodes
        guard filter.hasFilters else {
            if filterError != nil { filterError = nil }
            return sorted(nodes)
        }
        let matcher: SearchCriteriaMatcher
        do {
            matcher = try SearchCriteriaMatcher(filter)
        } catch {
            filterError = error.localizedDescription
            return []
        }
        if filterError != nil { filterError = nil }
        return sorted(nodes.filter(matcher.matches))
    }

    private func sorted(_ nodes: [FileNode]) -> [FileNode] {
        let ascending = sortDirection == .ascending
        let compareWithinGroup: (FileNode, FileNode) -> Bool = { [sortField, folderSizes] a, b in
            let isAscending: Bool
            switch sortField {
            case .name:
                isAscending = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateModified:
                isAscending = (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast)
            case .dateCreated:
                isAscending = (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
            case .dateAdded:
                isAscending = (a.dateAdded ?? .distantPast) < (b.dateAdded ?? .distantPast)
            case .dateLastOpened:
                isAscending = (a.lastOpenedDate ?? .distantPast) < (b.lastOpenedDate ?? .distantPast)
            case .size:
                // Folders sort by their calculated size once it's known.
                let sizeA = (a.isDirectory ? folderSizes[a.url] : a.size) ?? 0
                let sizeB = (b.isDirectory ? folderSizes[b.url] : b.size) ?? 0
                isAscending = sizeA < sizeB
            case .kind:
                isAscending = (a.kind ?? "").localizedStandardCompare(b.kind ?? "") == .orderedAscending
            case .tags:
                isAscending = a.tags.joined(separator: ",").localizedStandardCompare(b.tags.joined(separator: ",")) == .orderedAscending
            case .fileExtension:
                isAscending = a.fileExtension.localizedStandardCompare(b.fileExtension) == .orderedAscending
            case .location:
                isAscending = a.url.deletingLastPathComponent().path.localizedStandardCompare(b.url.deletingLastPathComponent().path) == .orderedAscending
            }
            return ascending ? isAscending : !isAscending
        }

        guard let groupBy else {
            return nodes.sorted(by: compareWithinGroup)
        }
        return nodes.sorted { a, b in
            let groupA = FileGrouping.group(for: a, by: groupBy)
            let groupB = FileGrouping.group(for: b, by: groupBy)
            if groupA.rank != groupB.rank { return groupA.rank < groupB.rank }
            if groupA.label != groupB.label {
                return groupA.label.localizedStandardCompare(groupB.label) == .orderedAscending
            }
            return compareWithinGroup(a, b)
        }
    }

    // MARK: Search field focus

    /// Called by the window's `/` shortcut (`MainWindowView`).
    /// Switches the current folder to `mode` and remembers it for that folder.
    func setViewMode(_ mode: FileViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        if let currentDirectory {
            folderViewModes.setMode(mode, for: currentDirectory)
        }
    }

    // MARK: Folder sizes

    /// Context menu ▸ Calculate Size, for folders while Calculate All is off.
    /// View ▸ Calculate Folder Sizes: every folder in the current view,
    /// once. (Settings ▸ General ▸ Always calculate folder sizes is what
    /// makes it automatic.)
    func calculateFolderSizesInView() {
        calculateFolderSizes(items.filter { $0.isDirectory && !$0.isPackage })
    }

    func calculateFolderSizes(_ nodes: [FileNode]) {
        let folders = nodes.filter(\.isDirectory).map(\.url)
        requestedFolderSizes.formUnion(folders)
        queueFolderSizes(folders)
    }

    private var calculatesAllFolderSizes: Bool { folderSizePreferences.calculateAll }

    private func resetFolderSizes() {
        folderSizeGeneration += 1
        folderSizeWorker?.cancel()
        folderSizeWorker = nil
        pendingFolderSizes = []
        folderSizes = [:]
        calculatingFolderSizes = []
        requestedFolderSizes = []
    }

    /// Arriving in a folder: show any sizes worked out before right away;
    /// `queueMissingFolderSizes` then re-checks them.
    private func showCachedFolderSizes() {
        guard calculatesAllFolderSizes else { return }
        for node in unsortedItems where node.isDirectory {
            if let cached = folderSizeCache.size(of: node.url) { folderSizes[node.url] = cached }
        }
    }

    /// With Calculate All on, queues every folder that has no size yet — or,
    /// on arrival (`revalidateAll`), every folder, since cached sizes may be
    /// out of date. A live refresh only adds folders that just appeared.
    private func queueMissingFolderSizes(revalidateAll: Bool) {
        guard calculatesAllFolderSizes else { return }
        let folders = unsortedItems.filter(\.isDirectory).map(\.url)
        queueFolderSizes(revalidateAll ? folders : folders.filter { folderSizes[$0] == nil })
    }

    private func calculateAllFolderSizesChanged(_ calculateAll: Bool) {
        if calculateAll {
            showCachedFolderSizes()
            if sortField == .size { items = filteredAndSorted(unsortedItems) }
            queueMissingFolderSizes(revalidateAll: true)
        } else {
            let requested = requestedFolderSizes
            resetFolderSizes()
            requestedFolderSizes = requested
            if sortField == .size { items = filteredAndSorted(unsortedItems) }
        }
    }

    /// Something changed inside the folder being shown: sizes of the
    /// subfolders it happened in are now wrong, so recalculate just those
    /// (the old figure stays up until the new one is ready).
    private func folderContentsChanged(_ changedPaths: Set<String>) {
        guard !changedPaths.isEmpty else { return }
        folderSizeCache.invalidate(containing: changedPaths)
        let affected = folderSizes.keys.filter { folder in
            let path = folder.resolvingSymlinksInPath().path
            return changedPaths.contains { $0 == path || $0.hasPrefix(path + "/") }
        }
        queueFolderSizes(affected.filter { calculatesAllFolderSizes || requestedFolderSizes.contains($0) })
    }

    private func queueFolderSizes(_ folders: [URL]) {
        let new = folders.filter { !pendingFolderSizes.contains($0) && !calculatingFolderSizes.contains($0) }
        guard !new.isEmpty else { return }
        pendingFolderSizes.append(contentsOf: new)
        startFolderSizeWorker()
    }

    /// Works through `pendingFolderSizes` three at a time — enough to keep
    /// a fast disk busy without one huge folder holding up the rest.
    private func startFolderSizeWorker() {
        guard folderSizeWorker == nil else { return }
        let generation = folderSizeGeneration
        folderSizeWorker = Task {
            while !pendingFolderSizes.isEmpty, !Task.isCancelled {
                let batch = Array(pendingFolderSizes.prefix(3))
                pendingFolderSizes.removeFirst(batch.count)
                await withTaskGroup(of: Void.self) { group in
                    for folder in batch {
                        group.addTask { await self.calculateFolderSize(folder, generation: generation) }
                    }
                }
            }
            if folderSizeGeneration == generation { folderSizeWorker = nil }
        }
    }

    private func calculateFolderSize(_ folder: URL, generation: Int) async {
        calculatingFolderSizes.insert(folder)
        defer {
            if folderSizeGeneration == generation { calculatingFolderSizes.remove(folder) }
        }
        guard let size = try? await folderSizeService.size(of: folder),
              folderSizeGeneration == generation else { return } // cancelled, or navigated away meanwhile
        folderSizes[folder] = size
        folderSizeCache.store(size, for: folder)
        if sortField == .size { items = filteredAndSorted(unsortedItems) }
    }

    func beginEditingAddress() {
        addressEditTrigger += 1
    }

    /// Opens `url` in a new tab, via the same hand-off Compress uses.
    func requestOpenInNewTab(_ url: URL) {
        pendingOpenInNewTabDirectory = url
    }

    func focusSearchField() {
        searchFieldFocusTrigger += 1
    }

    func clearSelection() {
        // At once, not only when the file view reports back.
        if !selectedNodes.isEmpty { selectedNodes = [] }
        clearSelectionTrigger += 1
    }

    func triggerQuickLook() {
        quickLookTrigger += 1
    }

    // MARK: Selection

    /// Called by `FileTableController.onSelectionChange` whenever the
    /// table's selection changes.
    func updateSelection(_ nodes: [FileNode]) {
        selectedNodes = nodes
    }

    /// After a reload, the selection's items are the old copies (with the
    /// old tags, size, dates) until the table reports a change — and when
    /// the same rows stay selected, it doesn't. Swap in the fresh ones so
    /// the Inspector shows what's on disk now.
    private func refreshSelectedNodes(from nodes: [FileNode]) {
        guard !selectedNodes.isEmpty else { return }
        let fresh = Dictionary(nodes.map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { first, _ in first })
        let updated = selectedNodes.compactMap { fresh[$0.url.standardizedFileURL] }
        if updated.count != selectedNodes.count || zip(updated, selectedNodes).contains(where: { $0 !== $1 }) {
            selectedNodes = updated
        }
    }

    // MARK: File operations

    func promptRename(_ node: FileNode) {
        pendingRenameNode = node
    }

    func promptBatchRename(_ nodes: [FileNode]) {
        pendingBatchRenameNodes = nodes
    }

    /// Applies a batch rename computed by `BatchRenameView` — all or
    /// nothing (see `BatchRenameService.apply`), undoable as one step.
    @discardableResult
    func applyBatchRename(urls: [URL], newNames: [String]) -> Task<Void, Never> {
        Task {
            do {
                let changes = try await BatchRenameService().apply(urls: urls, newNames: newNames)
                undoCenter.record(changes, actionName: changes.count == 1 ? "Rename" : "Rename \(changes.count) Items")
                await refresh()?.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func promptForNewFolder() {
        pendingNewFolderIntent = .inCurrentDirectory(andOpen: false)
    }

    func promptForNewFolderAndOpen() {
        pendingNewFolderIntent = .inCurrentDirectory(andOpen: true)
    }

    func promptForNewFolderHere(in node: FileNode) {
        pendingNewFolderIntent = .inside(node)
    }

    @discardableResult
    func createFolder(named name: String) -> Task<Void, Never>? {
        guard let intent = pendingNewFolderIntent else { return nil }
        pendingNewFolderIntent = nil

        switch intent {
        case .inCurrentDirectory(let andOpen):
            guard let directory = currentDirectory else { return nil }
            return Task {
                do {
                    let newFolderURL = try await fileSystemService.createFolder(named: name, in: directory)
                    undoCenter.record([.created(newFolderURL)], actionName: "New Folder")
                    if andOpen {
                        await navigate(to: newFolderURL).value
                    } else {
                        await refresh()?.value
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .inside(let node):
            return Task {
                do {
                    let newFolderURL = try await fileSystemService.createFolder(named: name, in: node.url)
                    undoCenter.record([.created(newFolderURL)], actionName: "New Folder")
                    await navigate(to: newFolderURL).value
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func promptForNewFile() {
        pendingNewFileIntent = true
    }

    @discardableResult
    func createFile(named name: String) -> Task<Void, Never>? {
        guard pendingNewFileIntent, let directory = currentDirectory else { return nil }
        pendingNewFileIntent = false
        return Task {
            do {
                let newFileURL = try await fileSystemService.createFile(named: name, in: directory)
                undoCenter.record([.created(newFileURL)], actionName: "New File")
                await refresh()?.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func rename(_ node: FileNode, to newName: String) -> Task<Void, Never> {
        Task {
            do {
                let renamedURL = try await fileSystemService.rename(node.url, to: newName)
                undoCenter.record([.moved(from: node.url, to: renamedURL)], actionName: "Rename")
                await refresh()?.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Asked when some items' volume has no Trash; `true` deletes them
    /// immediately. Tests replace the alert.
    @ObservationIgnored var confirmDeleteWithoutTrash: ([URL]) -> Bool = { Platform.confirmDeleteWithoutTrash($0) }

    @discardableResult
    func moveToTrash(_ nodes: [FileNode]) -> Task<Void, Never> {
        moveToTrash(urls: nodes.map(\.url))
    }

    /// Trashes what it can — Undo and Put Back cover those even if others
    /// couldn't go — and records it in File Operations, where Retry tries
    /// the rest again.
    @discardableResult
    func moveToTrash(urls: [URL]) -> Task<Void, Never> {
        let retry: @MainActor ([URL]) -> Void = { [weak self] remaining in
            self?.moveToTrash(urls: remaining)
        }
        return Task {
            let fallback = await TrashFallback.deleteItemsWithoutTrash(
                await fileSystemService.moveToTrash(urls),
                confirm: confirmDeleteWithoutTrash,
                fileSystemService: fileSystemService
            )
            let result = fallback.result
            var changes: [FileChange] = []
            for url in urls {
                guard let trashedURL = result.locations[url] else { continue }
                trashOriginService.recordOrigin(trashedURL: trashedURL, originalURL: url)
                changes.append(.trashed(original: url, trashedAt: trashedURL))
            }
            if !changes.isEmpty { undoCenter.record(changes, actionName: "Move to Trash") }
            Platform.progress.recordTrash(urls.filter { !fallback.deleted.contains($0) }, result: result, retry: retry)
            if let message = fallback.errorMessage {
                let shown = result.failures.filter { !result.withoutTrash.contains($0.url) }.count
                errorMessage = shown > 1
                    ? "\(shown) items couldn't be moved to the Trash. \(message)"
                    : message
            }
            await refresh()?.value
        }
    }

    // MARK: Trash (Restore / Delete Immediately)

    /// Restores each node to the location it was trashed from, if OneRoot
    /// itself recorded that when trashing it; otherwise prompts once per
    /// item for a destination, since the real original location generally
    /// isn't knowable (see `TrashOriginService`).
    @discardableResult
    func restore(_ nodes: [FileNode]) -> Task<Void, Never> {
        Task {
            var restored = 0
            var firstError: Error?
            var destinations: [URL] = []
            for node in nodes {
                do {
                    if let originalURL = trashOriginService.originalLocation(forTrashedURL: node.url) {
                        try await fileSystemService.restoreFromTrash(node.url, to: originalURL)
                        trashOriginService.removeRecord(forTrashedURL: node.url)
                        restored += 1
                        destinations.append(originalURL)
                    } else if let destination = await promptForRestoreDestination(itemName: node.name) {
                        try await fileSystemService.restoreFromTrash(node.url, to: destination.appendingPathComponent(node.name))
                        restored += 1
                        destinations.append(destination.appendingPathComponent(node.name))
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    firstError = firstError ?? error
                }
            }
            let outcome: FileOperationOutcome
            if let firstError {
                outcome = .failure(firstError, finished: restored, of: nodes.count)
            } else {
                // Nothing put back and nothing failed: every destination
                // prompt was cancelled.
                outcome = restored == 0 ? .cancelled : .succeeded
            }
            Platform.progress.record(
                title: FileOperationLabels.title("Putting back", nodes.map(\.url)),
                symbolName: "arrow.uturn.backward",
                outcome: outcome,
                itemCount: nodes.count,
                finishedItems: restored,
                destinationFolder: FileOperationLabels.commonFolder(destinations)
            )
            await refresh()?.value
        }
    }

    @discardableResult
    func deletePermanently(_ nodes: [FileNode]) -> Task<Void, Never> {
        Task {
            let urls = nodes.map(\.url)
            var outcome = FileOperationOutcome.succeeded
            do {
                try await fileSystemService.deletePermanently(urls)
                for node in nodes { trashOriginService.removeRecord(forTrashedURL: node.url) }
            } catch {
                errorMessage = error.localizedDescription
                outcome = .failure(error, finished: Self.goneCount(urls), of: urls.count)
            }
            // No Retry: deleting for good should always be asked for again.
            Platform.progress.record(
                title: FileOperationLabels.title("Deleting", urls, suffix: " immediately"),
                symbolName: "xmark.bin",
                outcome: outcome,
                itemCount: urls.count,
                finishedItems: outcome.isFailure ? Self.goneCount(urls) : urls.count,
                sourceFolder: FileOperationLabels.commonFolder(urls)
            )
            await refresh()?.value
        }
    }

    /// How many of `urls` no longer exist — what a delete that stopped
    /// partway did get to.
    nonisolated static func goneCount(_ urls: [URL]) -> Int {
        TrashFallback.goneCount(urls)
    }

    /// Presents `FileChooserView` (via `pendingRestoreDestinationItemName` —
    /// `FileListView` shows the sheet whenever it's non-nil) and suspends
    /// until `resolveRestoreDestination` is called, same continuation
    /// pattern as `resolveConflict` below.
    private func promptForRestoreDestination(itemName: String) async -> URL? {
        pendingRestoreDestinationItemName = itemName
        return await withCheckedContinuation { continuation in
            self.restoreDestinationContinuation = continuation
        }
    }

    /// Called by `FileListView` once the user picks a folder or cancels
    /// (`url == nil`) the restore-destination chooser.
    func resolveRestoreDestination(_ url: URL?) {
        pendingRestoreDestinationItemName = nil
        restoreDestinationContinuation?.resume(returning: url)
        restoreDestinationContinuation = nil
    }

    // MARK: Archives (Compress / Extract)

    /// Whether "Extract" should show for this selection — every item's
    /// extension has to be one the currently-configured engine can actually
    /// pull apart (see `ArchiveTool.extractableExtensions`).
    func canExtract(_ nodes: [FileNode]) -> Bool {
        guard !nodes.isEmpty else { return false }
        let extractable = archiveSettings.tool().extractableExtensions
        return nodes.allSatisfy { !$0.isDirectory && extractable.contains($0.fileExtension.lowercased()) }
    }

    /// Compresses `nodes` into a single archive, using whichever engine and
    /// output location Settings > Archives has configured — see
    /// `ArchiveSettingsService`. A single item keeps its full name
    /// ("notes.txt" → "notes.txt.zip", matching Finder); multiple items
    /// bundle into "Archive.zip", also matching Finder.
    @discardableResult
    func compressSelection(_ nodes: [FileNode]) -> Task<Void, Never>? {
        guard !nodes.isEmpty else { return nil }
        let baseName = nodes.count == 1 ? nodes[0].name : "Archive"

        return Task {
            let directory: URL?
            switch archiveSettings.outputLocation() {
            case .sameAsSource:
                directory = nodes.first?.url.deletingLastPathComponent()
            case .fixedDirectory:
                directory = archiveSettings.fixedDirectory() ?? nodes.first?.url.deletingLastPathComponent()
            case .askEachTime:
                directory = await promptForArchiveDestination(itemName: baseName)
            }
            guard let directory else { return }

            archiveOperationStatus = nodes.count == 1
                ? "Compressing \u{201C}\(nodes[0].name)\u{201D}…"
                : "Compressing \(nodes.count) items…"
            defer { archiveOperationStatus = nil }
            do {
                _ = try await archiveService.compress(
                    nodes.map(\.url),
                    into: directory,
                    baseName: baseName,
                    tool: archiveSettings.tool(),
                    format: archiveSettings.format()
                )
                await refresh()?.value
                pendingOpenInNewTabDirectory = directory
            } catch is CancellationError {
                // Cancelled from the operation's own progress popup —
                // not a failure worth surfacing as an error.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Called by `FileListView` once it's acted on
    /// `pendingOpenInNewTabDirectory` (opened the new tab).
    func clearPendingOpenInNewTabDirectory() {
        pendingOpenInNewTabDirectory = nil
    }

    /// Extracts each of `nodes` into a same-named subfolder inside a
    /// destination the user picks — extraction always asks, unlike
    /// compressing, which only asks when Settings says to.
    @discardableResult
    func extractSelection(_ nodes: [FileNode]) -> Task<Void, Never>? {
        guard !nodes.isEmpty else { return nil }
        let itemName = nodes.count == 1 ? nodes[0].name : "\(nodes.count) items"

        return Task {
            guard let directory = await promptForExtractDestination(itemName: itemName) else { return }
            let tool = archiveSettings.tool()

            archiveOperationStatus = nodes.count == 1
                ? "Extracting \u{201C}\(nodes[0].name)\u{201D}…"
                : "Extracting \(nodes.count) items…"
            defer { archiveOperationStatus = nil }
            do {
                for node in nodes {
                    _ = try await archiveService.extract(node.url, into: directory, tool: tool)
                }
                await refresh()?.value
            } catch is CancellationError {
                // Cancelled from the operation's own progress popup —
                // not a failure worth surfacing as an error.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Same continuation pattern as `promptForRestoreDestination` above.
    private func promptForArchiveDestination(itemName: String) async -> URL? {
        pendingArchiveDestinationItemName = itemName
        return await withCheckedContinuation { continuation in
            self.archiveDestinationContinuation = continuation
        }
    }

    /// Called by `FileListView` once the user picks a folder or cancels
    /// (`url == nil`) the archive-destination chooser.
    func resolveArchiveDestination(_ url: URL?) {
        pendingArchiveDestinationItemName = nil
        archiveDestinationContinuation?.resume(returning: url)
        archiveDestinationContinuation = nil
    }

    private func promptForExtractDestination(itemName: String) async -> URL? {
        pendingExtractDestinationItemName = itemName
        return await withCheckedContinuation { continuation in
            self.extractDestinationContinuation = continuation
        }
    }

    /// Called by `FileListView` once the user picks a folder or cancels
    /// (`url == nil`) the extract-destination chooser.
    func resolveExtractDestination(_ url: URL?) {
        pendingExtractDestinationItemName = nil
        extractDestinationContinuation?.resume(returning: url)
        extractDestinationContinuation = nil
    }

    /// The error banner's ✕.
    func dismissError() {
        errorMessage = nil
    }

    /// Shows `message` in the error banner — for failures that don't come
    /// through a file operation (tagging from the context menu).
    func reportError(_ message: String) {
        errorMessage = message
    }

    // MARK: Filter

    func clearFilter() {
        filter = filter.clearingFilters()
    }

    /// This folder's filter as an Advanced Search of it and everything
    /// inside — what Search Subfolders hands over.
    func filterAsSubfolderSearch() -> SearchCriteria? {
        guard let currentDirectory else { return nil }
        var criteria = filter
        criteria.root = currentDirectory
        criteria.mode = .nameAndMetadata
        criteria.includeHidden = showHiddenFiles
        return criteria
    }

    /// The filter as an Advanced Search of every folder in `workspace`.
    func filterAsWorkspaceSearch(_ workspace: Workspace) -> SearchCriteria? {
        guard let first = workspace.folders.first else { return nil }
        var criteria = filter
        criteria.root = first
        criteria.additionalRoots = Array(workspace.folders.dropFirst())
        criteria.workspaceName = workspace.name
        criteria.mode = .nameAndMetadata
        criteria.includeHidden = showHiddenFiles
        return criteria
    }

    /// After something made new files (a Quick Action): reports any error,
    /// reloads, and selects the new files that are in this folder.
    func showNewItems(_ created: [URL], error: Error?) async {
        if let error { errorMessage = error.localizedDescription }
        guard let folder = currentDirectory?.standardizedFileURL else { return }
        let here = created.filter { $0.deletingLastPathComponent().standardizedFileURL == folder }
        await refresh()?.value
        if !here.isEmpty {
            requestedSelection = Set(here)
            selectionRequest += 1
        }
    }

    // MARK: Copy / Cut / Paste

    /// Duplicate (⌘D), as in Finder: a copy of each item beside it, named
    /// "name (2)" — the same naming as Keep Both — then selects the
    /// copies. One Undo step for all of them.
    @discardableResult
    func duplicate(_ nodes: [FileNode]) -> Task<Void, Never>? {
        let urls = nodes.map(\.url)
        // Nothing is duplicated inside the Trash.
        guard !urls.isEmpty, !(currentDirectory.map(Platform.isTrashFolder) ?? false) else { return nil }
        // Items can come from several folders (Recents, the flat view).
        let byFolder = Dictionary(grouping: urls) { $0.deletingLastPathComponent() }
        return Task {
            let changeLog = FileChangeLog()
            for (folder, items) in byFolder.sorted(by: { $0.key.path < $1.key.path }) {
                do {
                    // Into their own folder: never a conflict to ask about.
                    try await fileSystemService.copyItems(items, to: folder, changeLog: changeLog, resolveConflicts: { _ in .cancel })
                } catch is CancellationError {
                    break
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            undoCenter.record(changeLog.changes, actionName: FileUndoCenter.actionName("Duplicate", items: urls))
            await refresh()?.value
            let copies = changeLog.changes.compactMap { change -> URL? in
                if case .created(let url) = change { return url }
                return nil
            }
            if !copies.isEmpty {
                requestedSelection = Set(copies)
                selectionRequest += 1
            }
        }
    }

    func copySelection(_ nodes: [FileNode]) {
        writeToPasteboard(nodes, operation: .copy)
    }

    func cutSelection(_ nodes: [FileNode]) {
        writeToPasteboard(nodes, operation: .cut)
    }

    private func writeToPasteboard(_ nodes: [FileNode], operation: ClipboardOperation) {
        guard !nodes.isEmpty else { return }
        clipboard.write(nodes.map(\.url), operation: operation)
        ClipboardTracker.shared.record(count: nodes.count, operation: operation)
    }

    func paste() {
        guard let directory = currentDirectory else { return }
        guard let (urls, isCut) = clipboard.files() else { return }
        let clipboard = self.clipboard
        transfer(urls, into: directory, move: isCut, onSuccess: {
            if isCut { clipboard.clear() } // consume the cut, like Explorer does
        })
    }

    // MARK: Drag and drop

    /// `directory` is `nil` for a background drop when this tab hasn't
    /// navigated anywhere yet (shouldn't normally happen, but there's no
    /// sensible target to fall back to).
    @discardableResult
    func handleDrop(urls: [URL], into directory: URL?, move: Bool) -> Task<Void, Never>? {
        guard let directory else { return nil }
        // Dropping something back into the folder it's already in is a
        // no-op for a move (there's nothing to move); for a copy it's a
        // legitimate "duplicate this file here" request, so only moves get
        // filtered.
        let urls = move ? urls.filter { $0.deletingLastPathComponent() != directory } : urls
        guard !urls.isEmpty else { return nil }
        return transfer(urls, into: directory, move: move)
    }

    /// Make Alias Here from the ⌃-drop menu. Each alias is undoable.
    @discardableResult
    func makeAliases(_ urls: [URL], in directory: URL?) -> Task<Void, Never>? {
        guard let directory, !urls.isEmpty else { return nil }
        return Task {
            do {
                let aliases = try await fileSystemService.makeAliases(to: urls, in: directory)
                undoCenter.record(aliases.map { .created($0) }, actionName: "Make Alias")
            } catch {
                errorMessage = error.localizedDescription
            }
            if directory == currentDirectory { refresh() }
        }
    }

    /// Copies or moves `urls` into `directory` — paste, drop, and a failed
    /// operation's Retry (with just the items that didn't finish). Records
    /// Undo for whatever completed, and reloads if `directory` is showing.
    @discardableResult
    /// `resolveConflicts` answers name collisions without asking (Compare
    /// Panes' sync); by default the user is asked.
    func transfer(
        _ urls: [URL],
        into directory: URL,
        move: Bool,
        resolveConflicts customResolver: (@MainActor (FileConflictRequest) async -> FileConflictAnswer)? = nil,
        onSuccess: (() -> Void)? = nil
    ) -> Task<Void, Never> {
        let retry: @MainActor @Sendable ([URL]) -> Void = { [weak self] remaining in
            self?.transfer(remaining, into: directory, move: move)
        }
        return Task {
            let changeLog = FileChangeLog()
            defer { recordUndo(changeLog, move: move, items: urls) }
            let resolver: (FileConflictRequest) async -> FileConflictAnswer = { request in
                if let customResolver { return await customResolver(request) }
                return await self.resolveConflicts(request)
            }
            guard let names = await NameFixCheck.plan(for: urls, into: directory, isMove: move, ask: { request in
                await self.askAboutNames(request)
            }) else { return }
            do {
                if move {
                    try await fileSystemService.moveItems(urls, to: directory, changeLog: changeLog, resolveConflicts: resolver, nameFixes: names.nameFixes, skipping: names.skipping, retry: retry)
                } else {
                    try await fileSystemService.copyItems(urls, to: directory, changeLog: changeLog, resolveConflicts: resolver, nameFixes: names.nameFixes, skipping: names.skipping, retry: retry)
                }
                onSuccess?()
                if directory == currentDirectory { await refresh()?.value }
            } catch is CancellationError {
                // Cancelled from the operation's own progress popup —
                // not a failure worth surfacing as an error.
            } catch {
                errorMessage = error.localizedDescription
                // The folder may hold the items that did make it.
                if directory == currentDirectory { refresh() }
            }
        }
    }

    /// Recorded even when the copy/move failed or was cancelled partway —
    /// whatever items did finish are still undoable.
    private func recordUndo(_ changeLog: FileChangeLog, move: Bool, items: [URL]) {
        recordReplacedItemOrigins(changeLog.changes, trashOriginService: trashOriginService)
        undoCenter.record(changeLog.changes, actionName: FileUndoCenter.actionName(move ? "Move" : "Copy", items: items))
    }

    private func resolveConflicts(_ request: FileConflictRequest) async -> FileConflictAnswer {
        conflictQueue.onChange = { [weak self] in self?.pendingConflicts = $0 }
        return await conflictQueue.ask(request)
    }

    /// Called by the UI with the user's answer to `pendingConflicts`.
    /// Names the destination can't store; the view asks (`NameFixSheet`).
    private(set) var pendingNameFix: NameFixRequest?
    private let nameFixQueue = NameFixQueue()

    private func askAboutNames(_ request: NameFixRequest) async -> NameFixAnswer {
        nameFixQueue.onChange = { [weak self] in self?.pendingNameFix = $0 }
        return await nameFixQueue.ask(request)
    }

    func answerNameFix(_ answer: NameFixAnswer, to id: UUID) {
        nameFixQueue.answer(answer, to: id)
    }

    func answerConflicts(_ answer: FileConflictAnswer, to id: UUID) {
        conflictQueue.answer(answer, to: id)
    }

    // MARK: Copy Path

    func copyPath(_ node: FileNode) {
        copyPaths([node.url])
    }

    /// Full paths, one per line — several selected items at once.
    /// Every tag used by something in this folder, for suggesting tags.
    var tagsInFolder: [[String]] { unsortedItems.map(\.tags) }

    /// Replaces `node`'s Finder tags, off the main thread, then reloads the
    /// folder so the list shows them. Returns why it failed, or `nil`.
    func setTags(_ tags: [String], for node: FileNode) async -> String? {
        let service = tagService
        let url = node.url
        do {
            try await Task.detached { try service.setTags(tags, on: url) }.value
        } catch {
            return "Couldn't change the tags of \u{201C}\(node.name)\u{201D}: \(error.localizedDescription)"
        }
        refresh()
        return nil
    }

    /// Adds `tag` to every one of `nodes` (`adding`), or takes it off them
    /// all — each item keeps its other tags. Items already that way are
    /// left alone. Several items show as an operation in File Operations
    /// (item by item, with Cancel, then in Completed). Returns what went
    /// wrong, if anything did.
    @discardableResult
    func setTag(_ tag: String, adding: Bool, on nodes: [FileNode]) async -> String? {
        let changes: [(url: URL, name: String, tags: [String])] = nodes.compactMap { node in
            let updated = adding ? TagService.adding(tag, to: node.tags) : TagService.removing(tag, from: node.tags)
            return updated == node.tags ? nil : (node.url, node.name, updated)
        }
        guard !changes.isEmpty else { return nil }
        let center = Platform.progress
        let cancellation = CancellationFlag()
        let urls = changes.map(\.url)
        let items = changes.count == 1 ? "\u{201C}\(changes[0].name)\u{201D}" : "\(changes.count) items"
        let progressID: UUID? = changes.count > 1
            ? center.begin(
                title: adding ? "Adding tag \u{201C}\(tag)\u{201D} to \(items)" : "Removing tag \u{201C}\(tag)\u{201D} from \(items)",
                symbolName: "tag",
                totalBytes: 0,
                isIndeterminate: true,
                sourceFolder: FileOperationLabels.commonFolder(urls),
                itemCount: changes.count,
                opensFloatingWindow: false,
                cancel: { cancellation.cancel() }
            )
            : nil

        let service = tagService
        let result = await Task.detached { () -> (done: Int, failure: (name: String, error: Error)?) in
            for (index, change) in changes.enumerated() {
                if cancellation.isCancelled { return (index, nil) }
                if let progressID {
                    let name = change.name
                    await MainActor.run { center.setCurrentItem(progressID, index: index, name: name) }
                }
                do {
                    try service.setTags(change.tags, on: change.url)
                } catch {
                    return (index, (change.name, error))
                }
            }
            return (changes.count, nil)
        }.value

        if let progressID {
            if let failure = result.failure {
                center.finish(progressID, outcome: .failure(failure.error, finished: result.done, of: changes.count), finishedItems: result.done)
            } else if cancellation.isCancelled, result.done < changes.count {
                center.finish(progressID, outcome: .cancelled, finishedItems: result.done)
            } else {
                center.finish(progressID)
            }
        }
        await refresh()?.value
        guard let failure = result.failure else { return nil }
        return "Couldn't change the tags of \u{201C}\(failure.name)\u{201D}: \(failure.error.localizedDescription)"
    }

    /// Shows `url` in the list: goes to the folder it's in, then selects it.
    func reveal(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        Task {
            if folder.standardizedFileURL != currentDirectory?.standardizedFileURL {
                await navigate(to: folder).value
            }
            requestedSelection = [url]
            selectionRequest += 1
        }
    }

    func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        clipboard.write(text: urls.map(\.path).joined(separator: "\n"))
    }

    /// The items' names, one per line — see `CopyableName`.
    func copyNames(_ nodes: [FileNode], includeExtension: Bool) {
        guard !nodes.isEmpty else { return }
        clipboard.write(text: CopyableName.text(for: nodes, includeExtension: includeExtension))
    }
}
