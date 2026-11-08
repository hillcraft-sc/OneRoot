import AppKit
import Combine

/// Manually drives the context menu instead of relying on AppKit's automatic
/// `view.menu` popup path — that automatic path was failing to display
/// anything at all in testing (AppKit itself logged `Connection with remote
/// prompt field terminated (com.apple.ViewBridge.error error 18)` on every
/// right-click).
final class ContextMenuOutlineView: NSOutlineView, NSMenuItemValidation {
    /// ⌘O to open the selected node — mirrors `FileTableView.onOpen`, since
    /// `NSOutlineView` (like `NSTableView`) doesn't forward key equivalents
    /// through `doCommand(by:)` reliably.
    var onOpen: (() -> Void)?
    var onRevealInFinderKey: (() -> Void)?
    var onEjectKey: (() -> Void)?

    private(set) var isBackgroundRightClick = false
    /// True only for the duration of the row-selecting call below, so
    /// `outlineViewSelectionDidChange` can tell "this selection change is
    /// just to give the context menu something to act on" apart from a
    /// real click — right-clicking a different tree row should highlight
    /// it and show its menu without navigating the active tab there.
    private(set) var isRightClickSelecting = false

    // Edit ▸ Undo/Redo act on file operations while the tree has focus —
    // see `FileUndoCenter`.
    @objc func undo(_ sender: Any?) { FileUndoCenter.shared.undo() }
    @objc func redo(_ sender: Any?) { FileUndoCenter.shared.redo() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        FileUndoCenter.shared.validate(menuItem) ?? true
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "o": onOpen?()
        case "l": onRevealInFinderKey?()
        case "j": onEjectKey?()
        default: super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        isBackgroundRightClick = clickedRow < 0
        if clickedRow >= 0, !selectedRowIndexes.contains(clickedRow) {
            isRightClickSelecting = true
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            isRightClickSelecting = false
        }
        guard let menu else {
            super.rightMouseDown(with: event)
            return
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.popUp(positioning: nil, at: point, in: self)
    }
}

/// Owns the `NSOutlineView` and is the source of truth for expansion state.
/// SwiftUI never rebuilds this tree on re-render — `FolderHierarchyView`
/// only pushes data in and reads selection out (see CLAUDE.md gotchas).
///
/// Lazy loading: a directory node with `children == nil` reports one
/// placeholder row so its disclosure triangle appears, kicks off an async
/// load, then reloads the item in place once real children arrive.
///
/// Top level: the hierarchy roots (`FolderHierarchyViewModel.roots`) — one
/// normally, each a labeled row that starts expanded. `item == nil` means
/// "the root list," distinct from any one root's own children. Switching
/// roots (another tab, another destination) remembers what was expanded
/// under the old one and puts it back when that root returns.
@MainActor
final class FolderOutlineViewController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let outlineView: ContextMenuOutlineView

    var onSelect: ((FileNode) -> Void)?
    var onEject: ((FileNode) -> Void)?
    var onOpenInNewTab: ((FileNode) -> Void)?
    var onCopy: ((FileNode) -> Void)?
    var onCut: ((FileNode) -> Void)?
    var onPaste: ((FileNode) -> Void)?
    var onRename: ((FileNode) -> Void)?
    var onMoveToTrash: ((FileNode) -> Void)?
    var onNewFolder: ((FileNode) -> Void)?
    var onTogglePin: ((FileNode) -> Void)?
    var onCopyPath: ((FileNode) -> Void)?
    var onCopyName: ((FileNode) -> Void)?
    var onEmptyTrash: ((FileNode) -> Void)?
    var canPaste: (() -> Bool)?
    var isPinned: ((FileNode) -> Bool)?
    var onDrop: ((_ urls: [URL], _ targetNode: FileNode, _ move: Bool) -> Void)?
    var onMakeAliases: ((_ urls: [URL], _ targetNode: FileNode) -> Void)?

    private var rootNodes: [FileNode] = []
    /// Above zero while this controller changes the tree itself (reloads,
    /// expanding, revealing). Selection changes then are side effects, not
    /// the user choosing a folder — acting on them would navigate the tab,
    /// often from inside a SwiftUI update, which SwiftUI doesn't allow.
    private var programmaticChangeDepth = 0

    private func withoutNavigating(_ body: () -> Void) {
        programmaticChangeDepth += 1
        defer { programmaticChangeDepth -= 1 }
        body()
    }
    /// What was expanded under each root the last time it was shown, by
    /// root URL — restored when the tree is rooted there again.
    private var expandedURLsByRoot: [URL: Set<URL>] = [:]
    private var ejectableRootURLs: Set<URL>
    private let childLoader: (FileNode) async -> [FileNode]
    private var loadingURLs: Set<URL> = []
    private var lastHandledCollapseAllCount = 0
    private var lastHandledRefreshAllCount = 0
    private var lastHandledExpandTopLevelCount = 0

    private static let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private let accountPictureService = AccountPictureService()
    /// Fetched once and reused — an OpenDirectory lookup on every row
    /// redraw would be wasteful, and the account picture won't change
    /// mid-session in any way this app needs to react to.
    private lazy var accountImage: NSImage? = accountPictureService.currentUserImageData().flatMap(NSImage.init(data:))

    private var allRootNodes: [FileNode] { rootNodes }

    /// Follows `ThemeStore`; see `apply(_:)`.
    private var theme = ThemeStore.shared.current
    private var themeWatch: ObservationWatch?

    init(
        roots: [FileNode],
        ejectableRootURLs: Set<URL>,
        childLoader: @escaping (FileNode) async -> [FileNode]
    ) {
        self.ejectableRootURLs = ejectableRootURLs
        self.childLoader = childLoader

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Name"

        let outlineView = ContextMenuOutlineView()
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 24
        // The single column must track the outline view's own width, not
        // grow to fit a long cell's content (a long pinned-folder or
        // cloud-provider name could otherwise drive the whole sidebar
        // pane wider) — cell text still just truncates instead.
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        self.outlineView = outlineView

        super.init()

        rootNodes = roots

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(handleDoubleClick)
        outlineView.onOpen = { [weak self] in self?.handleOpen() }
        outlineView.onRevealInFinderKey = { [weak self] in self?.handleRevealInFinder() }
        outlineView.onEjectKey = { [weak self] in self?.handleEject() }
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.every, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
        withoutNavigating {
            outlineView.reloadData() // register roots as known rows before expanding them
            for root in rootNodes {
                outlineView.expandItem(root)
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        themeWatch = ObservationWatch.watch({ ThemeStore.shared.current }) { [weak self] theme in
            self?.apply(theme)
        }
    }

    // MARK: Theme

    /// Recolors the tree: row selection, text, and icons. The background
    /// itself is painted by `FolderHierarchyView` (a `.themeBackground`), so the
    /// outline stays transparent here.
    ///
    /// A source list (macOS's own sidebar style) paints its own translucent
    /// material and its own accent-colored selection, neither of which a
    /// theme can change — so a theme with its own surfaces uses the plain
    /// style, where the background shows through and `ThemedRowView` draws
    /// the selection. The native themes keep the source list exactly as it
    /// was.
    private func apply(_ theme: Theme) {
        self.theme = theme
        outlineView.style = theme.surfaces == nil ? .sourceList : .plain
        outlineView.rowHeight = 24 // the style change resets it
        outlineView.backgroundColor = .clear
        // The scroll view's own opaque background would hide the theme's
        // sidebar color painted behind it; native keeps it as it was.
        outlineView.enclosingScrollView?.drawsBackground = theme.surfaces == nil
        // In place, not `reloadData()`, which would collapse every expanded
        // folder: recolor the row views that exist and have the cells
        // rebuilt. Selection and expansion carry over.
        outlineView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? ThemedRowView)?.selectionColor = theme.selectionNSColor
            rowView.needsDisplay = true
        }
        withoutNavigating {
            outlineView.reloadData(
                forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows),
                columnIndexes: IndexSet(integer: 0)
            )
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = ThemedRowView()
        rowView.selectionColor = theme.selectionNSColor
        return rowView
    }

    /// Applies a fresh root list. Only reloads when the roots themselves
    /// changed (by identity — `FolderHierarchyViewModel` reuses nodes);
    /// otherwise just refreshes the root rows in place.
    func updateRoots(_ newRoots: [FileNode], ejectableRootURLs: Set<URL>) {
        self.ejectableRootURLs = ejectableRootURLs
        withoutNavigating {
            guard newRoots.map(ObjectIdentifier.init) != rootNodes.map(ObjectIdentifier.init) else {
                for root in rootNodes { outlineView.reloadItem(root) }
                return
            }
            for root in rootNodes {
                expandedURLsByRoot[root.url] = expandedURLs(under: root)
            }
            rootNodes = newRoots
            outlineView.reloadData()
            for root in rootNodes {
                outlineView.expandItem(root)
                restoreExpansion(under: root, expanded: expandedURLsByRoot[root.url] ?? [])
            }
        }
    }

    /// Expanded folders under `node`, by URL. Only walks loaded children —
    /// nothing unloaded can be expanded.
    private func expandedURLs(under node: FileNode) -> Set<URL> {
        var urls: Set<URL> = []
        for child in node.children ?? [] where outlineView.isItemExpanded(child) {
            urls.insert(child.url)
            urls.formUnion(expandedURLs(under: child))
        }
        return urls
    }

    /// Re-expands what `expandedURLs(under:)` recorded. Only nodes whose
    /// children are already loaded are walked into; an expanded folder
    /// that isn't loaded yet loads lazily as `expandItem` asks for it.
    private func restoreExpansion(under node: FileNode, expanded: Set<URL>) {
        guard !expanded.isEmpty else { return }
        for child in node.children ?? [] where expanded.contains(child.url) {
            outlineView.expandItem(child)
            restoreExpansion(under: child, expanded: expanded)
        }
    }

    /// Handles a ⌘−/⌘+ request from `FolderHierarchyViewModel`. Requests are
    /// monotonic counters, not booleans — `updateNSView` runs on every
    /// SwiftUI re-render, so a counter lets this tell "a new request came
    /// in" apart from "nothing changed since I last checked," without
    /// needing SwiftUI-side state to clear a one-shot flag.
    func handleCollapseAllRequest(count: Int) {
        guard count != lastHandledCollapseAllCount else { return }
        lastHandledCollapseAllCount = count
        // Runs from `updateNSView`; collapsing can move the selection.
        withoutNavigating { collapseAll() }
    }

    func handleRefreshAllRequest(count: Int) {
        guard count != lastHandledRefreshAllCount else { return }
        lastHandledRefreshAllCount = count
        refreshAll()
    }

    /// Re-reads the roots and every expanded folder, keeping expansion
    /// (see `refetchChildren`). Folders loaded earlier but collapsed now
    /// just forget their children, so they're read fresh when next opened.
    func refreshAll() {
        var expanded: [FileNode] = []
        var pending = rootNodes
        while let node = pending.popLast() {
            guard let children = node.children else { continue }
            if rootNodes.contains(where: { $0 === node }) || outlineView.isItemExpanded(node) {
                expanded.append(node)
                pending.append(contentsOf: children)
            } else {
                node.children = nil
            }
        }
        for node in expanded { refetchChildren(of: node) }
    }

    func handleExpandTopLevelRequest(count: Int) {
        guard count != lastHandledExpandTopLevelCount else { return }
        lastHandledExpandTopLevelCount = count
        withoutNavigating { expandTopLevel() }
    }

    /// Collapses everything below each root. The roots themselves stay
    /// open — a collapsed root would leave the pane showing one row.
    func collapseAll() {
        for root in rootNodes {
            for child in root.children ?? [] {
                outlineView.collapseItem(child, collapseChildren: true)
            }
        }
    }

    /// Expands each root one level (its direct children only). Not a
    /// recursive expand-everything: a root can be a whole volume, so that
    /// would mean lazily loading and expanding every folder on the disk.
    func expandTopLevel() {
        for root in rootNodes {
            outlineView.expandItem(root)
        }
    }

    /// Expands every ancestor of `url` and selects it, if it's within one of
    /// these root volumes and already reachable (loading intermediate
    /// levels as needed).
    func reveal(url: URL) {
        // Resolved, not just standardized — FSEvents (and some volume/mount
        // paths) report paths through resolved symlinks (e.g. `/private/
        // var/...` instead of `/var/...`), which `standardizedFileURL`
        // alone doesn't normalize away.
        let target = url.resolvingSymlinksInPath()
        let matchingRoot = allRootNodes
            .filter { target.pathComponents.starts(with: $0.url.resolvingSymlinksInPath().pathComponents) }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
        guard let matchingRoot else { return }

        Task {
            let rootComponents = matchingRoot.url.resolvingSymlinksInPath().pathComponents
            let targetComponents = target.pathComponents

            var current = matchingRoot
            for component in targetComponents.dropFirst(rootComponents.count) {
                if current.children == nil {
                    current.children = await childLoader(current)
                    withoutNavigating { outlineView.reloadItem(current, reloadChildren: true) }
                }
                guard let match = current.children?.first(where: { $0.name == component }) else { return }
                withoutNavigating { outlineView.expandItem(current) }
                current = match
            }

            let row = outlineView.row(forItem: current)
            guard row >= 0 else { return }
            // The tab is already there — selecting the row mustn't navigate
            // it again (which used to reload the folder and clear its filter).
            withoutNavigating { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            outlineView.scrollRowToVisible(row)
        }
    }

    /// Re-fetches a node's children from disk — used after a New
    /// Folder/Rename/Trash/Paste initiated from this tree's own context
    /// menu, or an external change reported by `FolderHierarchyViewModel`'s file
    /// watcher. Only walks nodes whose children are already loaded, which
    /// holds here: the node that was right-clicked (or its parent) must
    /// already be visible on screen.
    func refreshChildren(of url: URL) {
        let target = url.resolvingSymlinksInPath()
        let matchingRoot = allRootNodes
            .filter { target.pathComponents.starts(with: $0.url.resolvingSymlinksInPath().pathComponents) }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
        guard let matchingRoot else { return }

        if matchingRoot.url.resolvingSymlinksInPath() == target {
            refetchChildren(of: matchingRoot)
            return
        }

        var current = matchingRoot
        let rootComponents = matchingRoot.url.resolvingSymlinksInPath().pathComponents
        for component in target.pathComponents.dropFirst(rootComponents.count) {
            guard let match = current.children?.first(where: { $0.name == component }) else { return }
            current = match
        }
        refetchChildren(of: current)
    }

    private func loadChildrenIfNeeded(_ node: FileNode) {
        guard node.children == nil, !loadingURLs.contains(node.url) else { return }
        loadingURLs.insert(node.url)
        Task {
            let children = await childLoader(node)
            node.children = children
            loadingURLs.remove(node.url)
            withoutNavigating { outlineView.reloadItem(node, reloadChildren: true) }
        }
    }

    /// Re-fetches an already-loaded node's children, reusing existing
    /// `FileNode` instances by URL for anything still present. Without
    /// this, refreshing swaps in brand-new objects for every child —
    /// including ones the user has expanded further down — which silently
    /// collapses them: `NSOutlineView` tracks expansion state by object
    /// identity, not by URL, so "the same folder" only stays expanded if
    /// it's literally the same `FileNode` instance. The tree only ever
    /// displays a node's name/icon/directory-ness (no dates or sizes), so
    /// reusing the old object for anything whose URL is unchanged loses
    /// nothing visible — a rename changes the URL, so it's correctly
    /// treated as a different entry instead of reused.
    private func refetchChildren(of node: FileNode) {
        guard !loadingURLs.contains(node.url) else { return }
        let existingChildren = node.children
        loadingURLs.insert(node.url)
        Task {
            let freshChildren = await childLoader(node)
            node.children = Self.merged(freshChildren, reusing: existingChildren)
            loadingURLs.remove(node.url)
            withoutNavigating { outlineView.reloadItem(node, reloadChildren: true) }
        }
    }

    private static func merged(_ freshChildren: [FileNode], reusing existingChildren: [FileNode]?) -> [FileNode] {
        guard let existingChildren else { return freshChildren }
        let existingByURL = Dictionary(uniqueKeysWithValues: existingChildren.map { ($0.url, $0) })
        return freshChildren.map { existingByURL[$0.url] ?? $0 }
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNodes.count }
        guard let node = item as? FileNode, node.isDirectory else { return 0 }
        if let children = node.children { return children.count }
        loadChildrenIfNeeded(node)
        return 1 // placeholder row until the real count is known
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNodes[index] }
        guard let node = item as? FileNode else {
            return FileNode(url: URL(fileURLWithPath: "/"), name: "", isDirectory: false, size: nil, modificationDate: nil, kind: nil)
        }
        if let children = node.children, index < children.count {
            return children[index]
        }
        return FileNode(url: node.url, name: "", isDirectory: false, size: nil, modificationDate: nil, kind: nil)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    // MARK: Drag source

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FileNode, !node.name.isEmpty else { return nil }
        return node.url as NSURL
    }

    // MARK: Drop destination

    /// Only dropping onto an existing folder item is supported — there's no
    /// sensible target for a drop on the tree's background or between rows.
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let targetNode = item as? FileNode, targetNode.isDirectory, !targetNode.name.isEmpty else { return [] }
        guard let urls = info.draggedFileURLs, isValidDropTarget(targetNode.url, for: urls) else { return [] }
        return DropActionMenu.operation(for: info)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let targetNode = item as? FileNode, targetNode.isDirectory, !targetNode.name.isEmpty else { return false }
        guard let urls = info.draggedFileURLs, isValidDropTarget(targetNode.url, for: urls) else { return false }
        guard DropActionMenu.shouldAsk(for: info) else {
            onDrop?(urls, targetNode, info.draggingSourceOperationMask.contains(.move))
            return true
        }
        DropActionMenu.ask { [weak self] action in
            switch action {
            case .move: self?.onDrop?(urls, targetNode, true)
            case .copy: self?.onDrop?(urls, targetNode, false)
            case .alias: self?.onMakeAliases?(urls, targetNode)
            }
        }
        return true
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FolderCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        if node.name.isEmpty {
            cell.textField?.stringValue = "Loading…"
            cell.imageView?.image = nil
        } else {
            cell.textField?.stringValue = node.name
            cell.imageView?.image = icon(for: node)
        }
        // A root's full path — a Workspace's roots live in different places.
        cell.toolTip = rootNodes.contains { $0 === node } ? node.url.path : nil
        cell.textField?.textColor = theme.textNSColor
        return cell
    }

    /// Custom artwork for every row instead of the real macOS file icon:
    /// `.folder` covers the generic case (every ordinary subfolder,
    /// wherever it sits in the tree — see the `default`), and specific
    /// `kind` tags (`DestinationKind.nodeKindTag`) pick a more specific
    /// icon for the roots. Home is special-cased by URL rather than `kind`
    /// (it's tagged plain "Folder") so it
    /// can fall back to the generic folder icon if the account has no
    /// custom photo set.
    private func icon(for node: FileNode) -> NSImage? {
        if node.url == Self.homeURL, let accountImage {
            return accountImage
        }
        // A package (e.g. a .app bundle) gets its own real icon rather than
        // the generic folder artwork every other row uses — matches how
        // it's treated everywhere else now: a launchable item, not a
        // folder to browse into.
        if node.isPackage {
            return NSWorkspace.shared.icon(forFile: node.url.path)
        }
        switch node.kind {
        case "Pinned": return ThemedIcons.image(.pinned, theme: theme)
        case "Trash": return ThemedIcons.image(.trash, theme: theme)
        case "Boot Volume": return ThemedIcons.image(.drive, theme: theme)
        case "Network Volume": return ThemedIcons.image(.network, theme: theme)
        case "Volume": return ThemedIcons.image(.volume, theme: theme)
        case "Applications": return ThemedIcons.image(.applications, theme: theme)
        case "Cloud Storage": return ThemedIcons.image(.cloud, theme: theme)
        default: return ThemedIcons.image(.folder, theme: theme)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? FileNode)?.name.isEmpty == false
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !outlineView.isRightClickSelecting, programmaticChangeDepth == 0 else { return }
        guard let node = outlineView.item(atRow: outlineView.selectedRow) as? FileNode else { return }
        // Selecting a package (e.g. a .app bundle) shouldn't navigate the
        // file list into its Contents/ — that's what a plain click did
        // before packages were distinguished from ordinary folders.
        // Launching (double-click/⌘O) and deliberately browsing inside
        // (⌥⌘O, or "Show in File List") are handled separately below.
        guard !node.isPackage else { return }
        // A tick later, like the file list's selection reports: never
        // navigate from inside whatever update caused this.
        DispatchQueue.main.async { [weak self] in self?.onSelect?(node) }
    }

    // MARK: Context menu

    private var selectedNode: FileNode? {
        outlineView.item(atRow: outlineView.selectedRow) as? FileNode
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard !outlineView.isBackgroundRightClick,
              let node = selectedNode,
              node.isDirectory, !node.name.isEmpty
        else {
            return
        }

        // Pinned folders sit at the top level too, but they're not mount
        // points — they should behave like any other folder (cuttable,
        // renameable, unpinnable), unlike an actual volume/cloud/Trash root.
        let isPinnedNode = node.kind == "Pinned"
        let isMountPoint = !isPinnedNode && allRootNodes.contains { $0 === node }
        let isEjectable = ejectableRootURLs.contains(node.url)

        if node.isPackage {
            let openItem = makeItem("Open \"\(node.name)\"", #selector(handleOpen))
            openItem.keyEquivalent = "o"
            openItem.keyEquivalentModifierMask = .command
            menu.addItem(openItem)
        }
        menu.addItem(makeItem("Open \"\(node.name)\" in New Tab", #selector(handleOpenInNewTab)))
        let revealItem = makeItem("Show \"\(node.name)\" in File List", #selector(handleReveal))
        if node.isPackage {
            revealItem.keyEquivalent = "o"
            revealItem.keyEquivalentModifierMask = [.command, .option]
        }
        menu.addItem(revealItem)
        if isEjectable {
            let verb = node.kind == "Network Volume" ? "Disconnect" : "Eject"
            let ejectItem = makeItem("\(verb) \"\(node.name)\"", #selector(handleEject))
            ejectItem.keyEquivalent = "j"
            ejectItem.keyEquivalentModifierMask = .command
            menu.addItem(ejectItem)
        }
        menu.addItem(.separator())

        if !isMountPoint {
            menu.addItem(makeItem("Cut", #selector(handleCut)))
            menu.addItem(makeItem("Copy", #selector(handleCopy)))
        }
        let pasteItem = makeItem("Paste", #selector(handlePaste))
        pasteItem.isEnabled = canPaste?() ?? false
        menu.addItem(pasteItem)
        menu.addItem(.separator())

        if !isMountPoint {
            menu.addItem(makeItem("Rename", #selector(handleRename)))
            menu.addItem(makeItem("Move to Trash", #selector(handleMoveToTrash)))
            menu.addItem(.separator())
        }

        if !isMountPoint {
            let pinned = isPinned?(node) ?? false
            menu.addItem(makeItem(pinned ? "Remove from Sidebar" : "Pin to Sidebar", #selector(handleTogglePin)))
            menu.addItem(.separator())
        }

        menu.addItem(makeItem("Get Info", #selector(handleGetInfo)))
        menu.addItem(makeItem("Copy Path", #selector(handleCopyPath)))
        menu.addItem(makeItem("Copy Name", #selector(handleCopyName)))
        let revealInFinderItem = makeItem("Reveal in Finder", #selector(handleRevealInFinder))
        revealInFinderItem.keyEquivalent = "l"
        revealInFinderItem.keyEquivalentModifierMask = .command
        menu.addItem(revealInFinderItem)
        menu.addItem(makeItem("Open in Terminal", #selector(handleOpenInTerminal)))
        menu.addItem(.separator())

        let isTrashNode = node.kind == "Trash"
        if isTrashNode {
            menu.addItem(makeItem("Empty Trash", #selector(handleEmptyTrash)))
        } else {
            menu.addItem(makeItem("New Folder", #selector(handleNewFolder)))
        }
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func handleOpenInNewTab() {
        guard let node = selectedNode else { return }
        onOpenInNewTab?(node)
    }

    @objc private func handleReveal() {
        guard let node = selectedNode else { return }
        onSelect?(node)
    }

    /// Double-clicking a package launches it (matching the file list);
    /// double-clicking anything else falls back to the outline view's
    /// normal expand/collapse, which setting `doubleAction` otherwise
    /// disables.
    @objc private func handleDoubleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode, !node.name.isEmpty else { return }
        guard node.isPackage else {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
            return
        }
        NSWorkspace.shared.open(node.url)
    }

    /// ⌘O launches a selected package; ⌥⌘O browses into it instead (same
    /// override as the file list's Open). For a non-package node this is
    /// just "Show in File List" under another name.
    @objc private func handleOpen() {
        guard let node = selectedNode else { return }
        let forceReveal = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        if node.isPackage, !forceReveal {
            NSWorkspace.shared.open(node.url)
        } else {
            onSelect?(node)
        }
    }

    @objc private func handleEject() {
        guard let node = selectedNode else { return }
        onEject?(node)
    }

    @objc private func handleCut() {
        guard let node = selectedNode else { return }
        onCut?(node)
    }

    @objc private func handleCopy() {
        guard let node = selectedNode else { return }
        onCopy?(node)
    }

    @objc private func handlePaste() {
        guard let node = selectedNode else { return }
        onPaste?(node)
    }

    @objc private func handleRename() {
        guard let node = selectedNode else { return }
        onRename?(node)
    }

    @objc private func handleMoveToTrash() {
        guard let node = selectedNode else { return }
        guard TrashConfirmation.confirm([node.name]) else { return }
        onMoveToTrash?(node)
    }

    @objc private func handleTogglePin() {
        guard let node = selectedNode else { return }
        onTogglePin?(node)
    }

    @objc private func handleCopyName() {
        guard let node = selectedNode else { return }
        onCopyName?(node)
    }

    @objc private func handleCopyPath() {
        guard let node = selectedNode else { return }
        onCopyPath?(node)
    }

    @objc private func handleRevealInFinder() {
        guard let node = selectedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func handleNewFolder() {
        guard let node = selectedNode else { return }
        onNewFolder?(node)
    }

    @objc private func handleOpenInTerminal() {
        guard let node = selectedNode else { return }
        openInTerminal(node.url)
    }

    @objc private func handleEmptyTrash() {
        guard let node = selectedNode else { return }
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "This will permanently erase the items in the Trash. This can't be undone."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onEmptyTrash?(node)
    }

    @objc private func handleGetInfo() {
        guard let node = selectedNode else { return }
        let alert = NSAlert()
        alert.messageText = node.name
        let lines = [
            "Kind: \(node.kind ?? "Folder")",
            "Location: \(node.url.deletingLastPathComponent().path)",
        ]
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
