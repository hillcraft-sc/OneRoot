import Foundation
import Observation

/// The model behind `FileChooserView`, OneRoot's own file/folder picker:
/// where you are, Back/Forward/Up, a typed or pasted path, the folder tree
/// on the left, what's in the folder on the right, hidden items, and what
/// "Choose" would pick. All disk reads go through `FileSystemService`, off
/// the main actor; a read that finishes after you've moved on is dropped.
@MainActor
@Observable
final class FileChooserViewModel {
    struct Options {
        var canChooseFiles = false
        var canChooseDirectories = true
        /// Which files may be chosen; `nil` means any — only meaningful
        /// with `canChooseFiles`. Called off the main actor (it may read
        /// the disk). See `FileChooserView` for the Mac's, by file type.
        var allowsFile: (@Sendable (URL) -> Bool)? = nil
        var allowsMultipleSelection = false
    }

    /// A folder in the tree, flattened for display: `depth` is its indent.
    struct TreeRow: Identifiable, Equatable {
        let url: URL
        let name: String
        let depth: Int
        let isExpanded: Bool
        var id: URL { url }
    }

    private(set) var currentDirectory: URL
    private(set) var entries: [FileNode] = []
    private(set) var isLoading = false
    private(set) var listingError: String?
    private(set) var selection: Set<URL> = []
    private(set) var showsHidden: Bool
    private(set) var shortcutSections: [DestinationSection] = []
    private(set) var treeRoot: HierarchyRoot
    private(set) var treeRows: [TreeRow] = []
    /// The path field's text — the current folder's path until you type.
    var pathText: String
    private(set) var pathError: String?
    private(set) var suggestions: [String] = []

    let options: Options
    private let fileSystemService: FileSystemService
    private let homeURL: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    /// Subfolders of each folder the tree has read.
    private var treeChildren: [URL: [(url: URL, name: String)]] = [:]
    private var expanded: Set<URL> = []
    /// Bumped by every navigation and hidden-items toggle; a listing that
    /// comes back under an older value is stale.
    private var generation = 0

    init(
        startingAt url: URL,
        options: Options = Options(),
        showsHidden: Bool = false,
        fileSystemService: FileSystemService = FileSystemService(),
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let start = url.standardizedFileURL
        currentDirectory = start
        pathText = start.path
        self.options = options
        self.showsHidden = showsHidden
        self.fileSystemService = fileSystemService
        self.homeURL = homeURL
        let home = HierarchyRoot(url: homeURL, name: homeURL.lastPathComponent, kind: .home)
        treeRoot = HierarchyRootResolver.root(for: start, current: nil, candidates: [home])
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentDirectory.path != "/" }

    // MARK: Loading

    /// The first listing, the tree, and the shortcuts (Home, Pinned, Cloud,
    /// Locations). `shortcuts` is read off the main actor by the caller's
    /// default — see `FileChooserShortcuts`.
    func start(shortcuts: @escaping @Sendable () -> [DestinationSection] = FileChooserShortcuts.current) async {
        async let sections = Task.detached(priority: .userInitiated) { shortcuts() }.value
        await load()
        shortcutSections = await sections
        rerootTree()
        await revealCurrentInTree()
    }

    private func load() async {
        generation += 1
        let token = generation
        let directory = currentDirectory
        isLoading = true
        do {
            let nodes = try await fileSystemService.listDirectory(directory, includeHidden: showsHidden)
            let listable = await Self.listable(nodes, options: options)
            guard token == generation else { return }
            entries = listable
            listingError = nil
        } catch {
            guard token == generation else { return }
            entries = []
            listingError = error.localizedDescription
        }
        isLoading = false
    }

    /// Browsable folders always show (you walk through them to reach
    /// files); anything else only when files can be chosen, and of an
    /// allowed type if any were given. Off the main actor: reading content
    /// types touches the disk.
    nonisolated private static func listable(_ nodes: [FileNode], options: Options) async -> [FileNode] {
        await Task.detached(priority: .userInitiated) {
            nodes.filter { node in
                if isBrowsableFolder(node) { return true }
                guard options.canChooseFiles else { return false }
                return options.allowsFile?(node.url) ?? true
            }
        }.value
    }

    // MARK: Navigation

    func navigate(to url: URL) async {
        let target = url.standardizedFileURL
        guard target != currentDirectory else { return }
        backStack.append(currentDirectory)
        forwardStack.removeAll()
        await show(target)
    }

    func goBack() async {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectory)
        await show(previous)
    }

    func goForward() async {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectory)
        await show(next)
    }

    func goUp() async {
        guard canGoUp else { return }
        await navigate(to: currentDirectory.deletingLastPathComponent())
    }

    /// A shortcut on the left: go there and root the tree at it, even if
    /// the folder is also inside another root.
    func openShortcut(_ destination: Destination) async {
        treeRoot = destination.hierarchyRoot
        await navigate(to: destination.url)
        rebuildTreeRows()
    }

    private func show(_ url: URL) async {
        currentDirectory = url
        pathText = url.path
        pathError = nil
        suggestions = []
        selection = []
        rerootTree()
        async let tree: Void = revealCurrentInTree()
        await load()
        await tree
    }

    /// Double-click or Return on an item: a folder opens; anything else
    /// that can be chosen is returned as the choice.
    func open(_ url: URL) async -> [URL]? {
        guard let node = entry(at: url) else { return nil }
        if Self.isBrowsableFolder(node) {
            await navigate(to: node.url)
            return nil
        }
        return isSelectable(node) ? [node.url] : nil
    }

    /// The listed item at `url`, however its path is spelled
    /// (`/private/var` and `/var` are the same folder).
    private func entry(at url: URL) -> FileNode? {
        let path = url.standardizedFileURL.path
        return entries.first { $0.url.standardizedFileURL.path == path }
    }

    // MARK: Path field

    /// Go to a typed or pasted path. A file's path opens its folder with
    /// the file selected, when files can be chosen. Anything that isn't
    /// there is flagged without leaving the current folder.
    func submitPath() async {
        let text = pathText
        let result = await Task.detached(priority: .userInitiated) { () -> (Result<ResolvedAddress, PathResolutionError>, URL?) in
            let resolved = PathResolver().resolve(text)
            if case .failure(.notADirectory(let path)) = resolved {
                return (resolved, URL(fileURLWithPath: path))
            }
            return (resolved, nil)
        }.value
        switch result {
        case (.success(.local(let url)), _):
            pathError = nil
            await navigate(to: url)
        case (.success(.networkShare), _):
            pathError = "Connect to the share first (Go \u{25B8} Connect to Server), then choose it here."
        case (.failure(.notADirectory), let file?) where options.canChooseFiles:
            await navigate(to: file.deletingLastPathComponent())
            if let node = entry(at: file) { setSelection([node.url]) }
        case (.failure(.empty), _):
            pathText = currentDirectory.path
        case (.failure(let error), _):
            pathError = error.errorDescription
        }
        suggestions = []
    }

    /// Subfolders matching the last path component as you type.
    func updateSuggestions() async {
        let text = pathText
        guard text != currentDirectory.path,
              let (directory, prefix) = PathResolver().splitForAutocomplete(text) else {
            suggestions = []
            return
        }
        let names = await fileSystemService.suggestFolders(in: directory, includeHidden: showsHidden)
        guard pathText == text else { return } // typed on meanwhile
        suggestions = Array(
            names.filter { prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased()) }
                .filter { $0 != prefix }
                .prefix(8)
        )
    }

    /// Completes the path field with a suggestion, ready for the next one.
    func acceptSuggestion(_ name: String) async {
        guard let (directory, _) = PathResolver().splitForAutocomplete(pathText) else { return }
        pathText = directory.appendingPathComponent(name).path + "/"
        await updateSuggestions()
    }

    func cancelPathEditing() {
        pathText = currentDirectory.path
        pathError = nil
        suggestions = []
    }

    // MARK: Hidden items

    func setShowsHidden(_ shows: Bool) async {
        guard shows != showsHidden else { return }
        showsHidden = shows
        treeChildren = [:]
        selection = selection.filter { !$0.lastPathComponent.hasPrefix(".") || shows }
        await load()
        await reloadExpandedTree()
    }

    // MARK: Selection and choosing

    /// One item at a time unless multiple selection is on — then the item
    /// just added wins.
    func setSelection(_ urls: Set<URL>) {
        if options.allowsMultipleSelection || urls.count <= 1 {
            selection = urls
        } else {
            let added = urls.subtracting(selection)
            selection = Set([added.first ?? urls.first].compactMap { $0 })
        }
    }

    /// What Choose returns: the selected items that can be chosen, or the
    /// folder you're in when nothing is selected and folders can be chosen.
    var chosenURLs: [URL] {
        guard !selection.isEmpty else {
            return options.canChooseDirectories ? [currentDirectory] : []
        }
        return entries.filter { selection.contains($0.url) && isSelectable($0) }.map(\.url)
    }

    var canChoose: Bool { !chosenURLs.isEmpty }

    func isSelectable(_ node: FileNode) -> Bool {
        Self.isBrowsableFolder(node) ? options.canChooseDirectories : options.canChooseFiles
    }

    /// A real folder you can go into — not a file, and not a package like
    /// a `.app`, which is a folder on disk but one item everywhere in
    /// OneRoot.
    nonisolated static func isBrowsableFolder(_ node: FileNode) -> Bool {
        node.isDirectory && !node.isPackage
    }

    // MARK: Tree

    func toggleExpanded(_ url: URL) async {
        if expanded.contains(url) {
            expanded.remove(url)
            rebuildTreeRows()
        } else {
            expanded.insert(url)
            await loadTreeChildren(of: url)
            rebuildTreeRows()
        }
    }

    /// Roots the tree at the shortcut that holds the current folder most
    /// closely, keeping the current root while you stay inside it.
    private func rerootTree() {
        let candidates = shortcutSections.flatMap(\.destinations).map(\.hierarchyRoot)
            + [HierarchyRoot(url: homeURL, name: homeURL.lastPathComponent, kind: .home)]
        let root = HierarchyRootResolver.root(for: currentDirectory, current: treeRoot, candidates: candidates)
        if root != treeRoot {
            treeRoot = root
            expanded = []
        }
    }

    /// Expands the tree from its root down to the current folder.
    private func revealCurrentInTree() async {
        let rootComponents = treeRoot.url.standardizedFileURL.pathComponents
        let components = currentDirectory.pathComponents
        var folder = treeRoot.url.standardizedFileURL
        expanded.insert(folder)
        await loadTreeChildren(of: folder)
        if components.starts(with: rootComponents) {
            for component in components.dropFirst(rootComponents.count).dropLast() {
                folder.appendPathComponent(component, isDirectory: true)
                expanded.insert(folder)
                await loadTreeChildren(of: folder)
            }
        }
        rebuildTreeRows()
    }

    private func reloadExpandedTree() async {
        for folder in expanded {
            await loadTreeChildren(of: folder)
        }
        rebuildTreeRows()
    }

    private func loadTreeChildren(of folder: URL) async {
        guard treeChildren[folder] == nil else { return }
        let nodes = (try? await fileSystemService.listDirectory(folder, includeHidden: showsHidden)) ?? []
        treeChildren[folder] = nodes.filter(Self.isBrowsableFolder).map { ($0.url.standardizedFileURL, $0.name) }
    }

    private func rebuildTreeRows() {
        var rows: [TreeRow] = []
        func add(_ url: URL, name: String, depth: Int) {
            let isExpanded = expanded.contains(url)
            rows.append(TreeRow(url: url, name: name, depth: depth, isExpanded: isExpanded))
            guard isExpanded else { return }
            for child in treeChildren[url] ?? [] {
                add(child.url, name: child.name, depth: depth + 1)
            }
        }
        add(treeRoot.url.standardizedFileURL, name: treeRoot.name, depth: 0)
        if rows != treeRows { treeRows = rows }
    }

    /// Whether a tree folder has (or may have) subfolders worth a
    /// disclosure arrow — unknown until read, so unread folders get one.
    func mayHaveSubfolders(_ url: URL) -> Bool {
        treeChildren[url].map { !$0.isEmpty } ?? true
    }
}

/// The places the chooser lists on the left — the destination sidebar's,
/// minus Recents, Shared, and the Trash.
enum FileChooserShortcuts {
    @Sendable static func current() -> [DestinationSection] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pinned = PinnedLocationsService().load()
        let cloud = CloudStorageLocationsService().discover()
        let volumes = Platform.currentVolumes()
        return sections(home: home, pinned: pinned, cloud: cloud, volumes: volumes)
    }

    static func sections(home: URL, pinned: [URL], cloud: [URL], volumes: [VolumeInfo]) -> [DestinationSection] {
        var result = [DestinationSection(id: "home", title: "", destinations: [
            Destination(url: home, name: home.lastPathComponent, kind: .home),
        ])]
        if !pinned.isEmpty {
            result.append(DestinationSection(id: "pinned", title: "Pinned", destinations: pinned.map {
                Destination(url: $0, name: $0.lastPathComponent, kind: .pinned)
            }))
        }
        if !cloud.isEmpty {
            result.append(DestinationSection(id: "cloud", title: "Cloud", destinations: cloud
                .map { Destination(url: $0, name: $0.friendlyFolderName, kind: .cloud) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
        }
        var locations: [Destination] = []
        if let boot = volumes.first(where: { $0.url.path == "/" }) {
            locations.append(Destination(url: boot.url, name: boot.name, kind: .bootVolume))
        }
        locations.append(Destination(url: URL(fileURLWithPath: "/Applications"), name: "Applications", kind: .applications))
        locations += volumes
            .filter { $0.url.path != "/" }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Destination(url: $0.url, name: $0.name, kind: $0.isLocal ? .volume : .networkVolume) }
        result.append(DestinationSection(id: "locations", title: "Locations", destinations: locations))
        return result
    }
}
