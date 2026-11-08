import Foundation
import Observation

/// The folder-hierarchy pane's model: the `NSOutlineView` tree rooted at
/// whatever the active tab's `HierarchyRoot` is (one root normally, more
/// once Workspaces exist), plus every file operation the tree's own
/// context menu and drag-and-drop can start.
///
/// Global places (volumes, pins, cloud, Trash) are `DestinationsViewModel`'s
/// job; this only shows the roots it's handed via `setRoots(_:)`.
@MainActor
@Observable
final class FolderHierarchyViewModel {
    /// The tree's top-level rows. Reused by URL across `setRoots` calls (see
    /// `rootNodeCache`), so a root you come back to keeps its loaded children.
    private(set) var roots: [FileNode] = []
    var errorMessage: String?
    private(set) var pendingConflicts: FileConflictRequest?
    /// URLs whose tree node should re-fetch its children — after a New
    /// Folder/Rename/Trash/Paste initiated from the tree's own context menu,
    /// or an external change reported by `fileWatcher`. `FolderHierarchyView`
    /// observes this and clears each entry once handled.
    var refreshRequests: Set<URL> = []
    /// The last request to scroll to / select a URL in the tree — driven by
    /// the active tab's current directory (see `HierarchyCoordinator`).
    /// Only views that read it (`FolderHierarchyView`) redraw when it
    /// changes; the serial makes asking for the same folder again count.
    private(set) var revealRequest: RevealRequest?

    struct RevealRequest: Equatable {
        let url: URL
        let serial: Int
    }

    func reveal(_ url: URL) {
        revealRequest = RevealRequest(url: url, serial: (revealRequest?.serial ?? 0) &+ 1)
    }
    /// Monotonic counters, not booleans — see `FolderOutlineViewController.
    /// handleCollapseAllRequest`.
    var collapseAllRequestCount = 0
    var expandTopLevelRequestCount = 0
    var refreshAllRequestCount = 0
    /// Roots that are ejectable volumes or shares — pushed in from
    /// `DestinationsViewModel`, which owns volume state.
    private(set) var ejectableRootURLs: Set<URL> = []
    /// Ejects a root (the tree's Eject menu item). Set by the window to
    /// `DestinationsViewModel.eject(at:)`.
    @ObservationIgnored var ejectHandler: ((URL) -> Void)?

    private let fileSystemService: FileSystemService
    private let pinnedLocations: PinnedLocationsStore
    private let trashOriginService: TrashOriginService
    private let fileWatcher: FileWatching
    private let undoCenter: FileUndoCenter
    private let clipboard: FileClipboard
    /// Root nodes seen before, by URL — switching back to a tab or
    /// destination reuses the node (and its already-loaded children)
    /// instead of starting the tree over.
    @ObservationIgnored private var rootNodeCache: [URL: FileNode] = [:]
    private static let rootNodeCacheLimit = 24
    private let conflictQueue = FileConflictQueue()

    /// `fileWatcher` defaults to inert rather than watching real machine
    /// state, so tests stay hermetic; production (`MainWindowView`) passes a
    /// real `FileWatcher`.
    init(
        fileSystemService: FileSystemService = FileSystemService(),
        pinnedLocations: PinnedLocationsStore? = nil,
        trashOriginService: TrashOriginService = TrashOriginService(),
        fileWatcher: FileWatching = NullFileWatcher(),
        undoCenter: FileUndoCenter? = nil,
        clipboard: FileClipboard? = nil
    ) {
        self.undoCenter = undoCenter ?? .shared
        self.clipboard = clipboard ?? Platform.clipboard
        self.fileSystemService = fileSystemService
        self.pinnedLocations = pinnedLocations ?? .shared
        self.trashOriginService = trashOriginService
        self.fileWatcher = fileWatcher

        fileWatcher.onChange = { [weak self] in
            self?.handleExternalChange()
        }
    }

    /// Re-roots the tree. Publishes only when the visible roots actually
    /// change. FSEvents watches recursively, so watching just the roots is
    /// enough to hear about changes anywhere below them.
    func setRoots(_ newRoots: [HierarchyRoot]) {
        let nodes = newRoots.map { root -> FileNode in
            if let cached = rootNodeCache[root.url], cached.name == root.name, cached.kind == root.kind.nodeKindTag {
                return cached
            }
            let node = FileNode(url: root.url, name: root.name, isDirectory: true, size: nil, modificationDate: nil, kind: root.kind.nodeKindTag)
            // Carry already-loaded children over if only the name changed.
            node.children = rootNodeCache[root.url]?.children
            rootNodeCache[root.url] = node
            return node
        }
        guard nodes.map(ObjectIdentifier.init) != roots.map(ObjectIdentifier.init) else { return }

        let previousURLs = Set(roots.map(\.url))
        roots = nodes
        trimRootNodeCache()
        fileWatcher.watch(nodes.map(\.url))

        // A cached root wasn't watched while it was away: re-fetch whatever
        // of it is already loaded so changes made meanwhile show up.
        let reactivated = nodes.filter { !previousURLs.contains($0.url) && $0.children != nil }
        let stale = reactivated.flatMap(Self.loadedFolderURLs)
        if !stale.isEmpty { refreshRequests.formUnion(stale) }
    }

    private static func loadedFolderURLs(under node: FileNode) -> [URL] {
        guard let children = node.children else { return [] }
        return [node.url] + children.flatMap(loadedFolderURLs)
    }

    private func trimRootNodeCache() {
        guard rootNodeCache.count > Self.rootNodeCacheLimit else { return }
        let keep = Set(roots.map(\.url))
        for url in rootNodeCache.keys where !keep.contains(url) {
            rootNodeCache.removeValue(forKey: url)
            if rootNodeCache.count <= Self.rootNodeCacheLimit { break }
        }
    }

    func updateEjectableRootURLs(_ urls: Set<URL>) {
        if urls != ejectableRootURLs { ejectableRootURLs = urls }
    }

    private func handleExternalChange() {
        // One `formUnion` rather than a per-path `insert` loop — a single
        // filesystem change can be reported as several paths at once (e.g.
        // a new file plus its parent directory's own mtime bump), and each
        // mutation of a `@Published` property publishes separately.
        let parents = fileWatcher.drainChangedPaths().map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        guard !parents.isEmpty else { return }
        refreshRequests.formUnion(parents)
    }

    /// Loader handed to the outline view controller so it can lazily fetch a
    /// node's children without reaching into `FileManager` itself. Tree rows
    /// are folders only — files belong in the file list, not the tree.
    func children(of node: FileNode) async -> [FileNode] {
        ((try? await fileSystemService.listDirectory(node.url)) ?? []).filter(\.isDirectory)
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedLocations.isPinned(url)
    }

    func togglePin(_ node: FileNode) {
        pinnedLocations.toggle(node.url)
    }

    func eject(_ node: FileNode) {
        ejectHandler?(node.url)
    }

    // MARK: Copy / Cut / Paste (tree context menu)

    func copyNode(_ node: FileNode) {
        writeToPasteboard(node.url, operation: .copy)
    }

    func cutNode(_ node: FileNode) {
        writeToPasteboard(node.url, operation: .cut)
    }

    private func writeToPasteboard(_ url: URL, operation: ClipboardOperation) {
        clipboard.write([url], operation: operation)
        ClipboardTracker.shared.record(count: 1, operation: operation)
    }

    var canPaste: Bool {
        clipboard.hasFiles
    }

    @discardableResult
    func paste(into node: FileNode) -> Task<Void, Never>? {
        guard let (urls, isCut) = clipboard.files() else { return nil }
        let clipboard = self.clipboard
        let destination = node.url

        return Task {
            let changeLog = FileChangeLog()
            defer { recordUndo(changeLog, move: isCut, items: urls) }
            guard let names = await NameFixCheck.plan(for: urls, into: destination, isMove: isCut, ask: { [weak self] request in
                await self?.askAboutNames(request) ?? .cancel
            }) else { return }
            do {
                if isCut {
                    try await fileSystemService.moveItems(urls, to: destination, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: names.nameFixes, skipping: names.skipping)
                    clipboard.clear()
                } else {
                    try await fileSystemService.copyItems(urls, to: destination, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: names.nameFixes, skipping: names.skipping)
                }
                refreshRequests.insert(destination)
            } catch is CancellationError {
                refreshRequests.insert(destination) // whatever did finish
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// See `FileListViewModel.recordUndo`.
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

    // MARK: Drag and drop

    @discardableResult
    func handleDrop(urls: [URL], into node: FileNode, move: Bool) -> Task<Void, Never> {
        // See FileListViewModel.handleDrop: dropping something back into the
        // folder it's already in is a no-op for a move, but a legitimate
        // duplicate-here request for a copy.
        let urls = move ? urls.filter { $0.deletingLastPathComponent() != node.url } : urls

        return Task {
            guard !urls.isEmpty else { return }
            let changeLog = FileChangeLog()
            defer { recordUndo(changeLog, move: move, items: urls) }
            guard let names = await NameFixCheck.plan(for: urls, into: node.url, isMove: move, ask: { [weak self] request in
                await self?.askAboutNames(request) ?? .cancel
            }) else { return }
            do {
                if move {
                    try await fileSystemService.moveItems(urls, to: node.url, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: names.nameFixes, skipping: names.skipping)
                } else {
                    try await fileSystemService.copyItems(urls, to: node.url, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: names.nameFixes, skipping: names.skipping)
                }
                refreshRequests.insert(node.url)
            } catch is CancellationError {
                refreshRequests.insert(node.url) // whatever did finish
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Make Alias Here from the ⌃-drop menu. Each alias is undoable.
    @discardableResult
    func makeAliases(_ urls: [URL], in directory: URL) -> Task<Void, Never> {
        Task {
            do {
                let aliases = try await fileSystemService.makeAliases(to: urls, in: directory)
                undoCenter.record(aliases.map { .created($0) }, actionName: "Make Alias")
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshRequests.insert(directory)
        }
    }

    // MARK: Rename / New Folder / Move to Trash (tree context menu)

    @discardableResult
    func rename(_ node: FileNode, to newName: String) -> Task<Void, Never> {
        Task {
            do {
                let renamedURL = try await fileSystemService.rename(node.url, to: newName)
                undoCenter.record([.moved(from: node.url, to: renamedURL)], actionName: "Rename")
                refreshRequests.insert(node.url.deletingLastPathComponent())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func createFolder(in node: FileNode, named name: String) -> Task<Void, Never> {
        Task {
            do {
                let newFolderURL = try await fileSystemService.createFolder(named: name, in: node.url)
                undoCenter.record([.created(newFolderURL)], actionName: "New Folder")
                refreshRequests.insert(node.url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Asked when some items' volume has no Trash; `true` deletes them
    /// immediately. Tests replace the alert.
    @ObservationIgnored var confirmDeleteWithoutTrash: ([URL]) -> Bool = { Platform.confirmDeleteWithoutTrash($0) }

    @discardableResult
    func moveToTrash(_ node: FileNode) -> Task<Void, Never> {
        moveToTrash([node.url])
    }

    /// Also used for items dropped on the Trash destination, so they're
    /// trashed properly (origin recorded for Restore, undoable) rather than
    /// just moved into `~/.Trash`.
    @discardableResult
    func moveToTrash(_ urls: [URL]) -> Task<Void, Never> {
        let retry: @MainActor ([URL]) -> Void = { [weak self] remaining in
            self?.moveToTrash(remaining)
        }
        return Task {
            guard !urls.isEmpty else { return }
            let fallback = await TrashFallback.deleteItemsWithoutTrash(
                await fileSystemService.moveToTrash(urls),
                confirm: confirmDeleteWithoutTrash,
                fileSystemService: fileSystemService
            )
            let result = fallback.result
            for url in fallback.deleted { pinnedLocations.unpin(url) }
            var changes: [FileChange] = []
            for url in result.trashed {
                pinnedLocations.unpin(url) // a pinned folder that no longer exists is just a broken row
                guard let trashedURL = result.locations[url] else { continue }
                trashOriginService.recordOrigin(trashedURL: trashedURL, originalURL: url)
                changes.append(.trashed(original: url, trashedAt: trashedURL))
            }
            if !changes.isEmpty {
                undoCenter.record(changes, actionName: "Move to Trash")
            }
            Platform.progress.recordTrash(urls.filter { !fallback.deleted.contains($0) }, result: result, retry: retry)
            if let message = fallback.errorMessage { errorMessage = message }
            refreshRequests.formUnion(urls.map { $0.deletingLastPathComponent() })
        }
    }

    func copyName(_ node: FileNode, includeExtension: Bool) {
        clipboard.write(text: CopyableName.name(of: node, includeExtension: includeExtension))
    }

    func copyPath(_ node: FileNode) {
        clipboard.write(text: node.url.path)
    }

    // MARK: Trash (tree context menu)

    @discardableResult
    func emptyTrash(_ node: FileNode) -> Task<Void, Never> {
        Task {
            var contents: [URL] = []
            var outcome = FileOperationOutcome.succeeded
            do {
                // Hidden items count too (the Trash holds dotfiles as well).
                contents = try await fileSystemService.listDirectory(node.url, includeHidden: true).map(\.url)
                // One at a time: an item that has already gone (another app
                // emptied it, a stale entry) must not stop the rest.
                for url in contents {
                    do {
                        try await fileSystemService.deletePermanently([url])
                    } catch where FileSystemError.isMissing(error) {
                        // already gone
                    }
                    trashOriginService.removeRecord(forTrashedURL: url)
                }
            } catch where FileSystemError.isMissing(error) {
                // No Trash folder yet, or an item went away meanwhile: nothing left to empty.
            } catch {
                errorMessage = error.localizedDescription
                outcome = .failure(error, finished: FileListViewModel.goneCount(contents), of: contents.count)
            }
            Platform.progress.record(
                title: "Emptying the Trash",
                symbolName: "xmark.bin",
                outcome: outcome,
                itemCount: contents.count,
                finishedItems: outcome.isFailure ? FileListViewModel.goneCount(contents) : contents.count
            )
            refreshRequests.insert(node.url)
        }
    }

    // MARK: Collapse / Expand all (⌘−/⌘+)

    func requestCollapseAll() {
        collapseAllRequestCount += 1
    }

    func requestExpandTopLevel() {
        expandTopLevelRequestCount += 1
    }

    /// Re-reads every open folder in the tree (View ▸ Refresh).
    func requestRefreshAll() {
        refreshAllRequestCount += 1
    }
}
