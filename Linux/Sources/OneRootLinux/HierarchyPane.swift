import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The folder hierarchy pane: the active tab's `HierarchyRoot` (or a
/// Workspace's folders) as a lazily loaded tree of folders — the GTK
/// counterpart of the Mac's NSOutlineView over the shared
/// `FolderHierarchyViewModel`. The window's `HierarchyCoordinator` roots it
/// and asks it to reveal the current folder.
///
/// The visible rows are flattened into a ListBox (indent plus a disclosure
/// button); `expanded` and each node's `children` are the tree state.
@MainActor
final class HierarchyPane {
    private struct Row {
        let node: FileNode
        let depth: Int
        let isRoot: Bool
    }

    let widget: Box
    /// A row was clicked: browse to the folder.
    var onNavigate: ((URL) -> Void)?
    /// Open the folder in a new tab (middle-click, context menu).
    var onOpenInNewTab: ((URL) -> Void)?
    /// The shown folders are reported to the window for its context menu.
    var onCopyPath: ((URL) -> Void)?
    /// Files were dropped on a folder row.
    var onDrop: (([URL], _ folder: URL, _ move: Bool) -> Void)?

    private let model: FolderHierarchyViewModel
    private let list = ListBox()
    private let titleLabel = Label("")
    private var rows: [Row] = []
    private var expanded: Set<URL> = []
    private var loading: Set<URL> = []
    private var watches: [ObservationWatch] = []
    private var isSyncing = false
    private var selectedURL: URL?
    private var menu: PopoverMenu?
    private var showsHidden: () -> Bool = { false }

    init(model: FolderHierarchyViewModel, showsHidden: @escaping () -> Bool) {
        self.model = model
        self.showsHidden = showsHidden
        list.addCSSClass("navigation-sidebar")
        list.setAccessibleLabel("Folder hierarchy")
        list.selectionMode = GTK_SELECTION_SINGLE
        list.activateOnSingleClick = true

        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_AUTOMATIC, vertical: GTK_POLICY_AUTOMATIC)
        scroller.vexpand = true

        titleLabel.xalign = 0
        titleLabel.addCSSClass("caption-heading")
        titleLabel.addCSSClass(.dimLabel)
        titleLabel.ellipsize = PANGO_ELLIPSIZE_END
        titleLabel.marginStart = 12
        titleLabel.marginTop = 8
        titleLabel.marginBottom = 4
        titleLabel.setAccessibleLabel("Folder hierarchy")

        widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        widget.append(titleLabel)
        widget.append(scroller)
        widget.setSizeRequest(width: 160)

        list.onRowActivated { [weak self] row in
            guard let self, !self.isSyncing, row.index < self.rows.count else { return }
            self.onNavigate?(self.rows[row.index].node.url)
        }

        watches.append(ObservationWatch.watch({ model.roots.map(ObjectIdentifier.init) }) { [weak self] _ in
            self?.rootsChanged()
        })
        watches.append(ObservationWatch.watch({ model.revealRequest }, emitsInitialValue: false) { [weak self] request in
            guard let self, let request else { return }
            self.reveal(request.url)
        })
        watches.append(ObservationWatch.watch({ model.refreshRequests }, emitsInitialValue: false) { [weak self] requests in
            guard let self, !requests.isEmpty else { return }
            self.refresh(requests)
        })
        watches.append(ObservationWatch.watch({ model.collapseAllRequestCount }, emitsInitialValue: false) { [weak self] _ in
            self?.collapseAll()
        })
        watches.append(ObservationWatch.watch({ model.expandTopLevelRequestCount }, emitsInitialValue: false) { [weak self] _ in
            self?.expandTopLevel()
        })
        watches.append(ObservationWatch.watch({ model.refreshAllRequestCount }, emitsInitialValue: false) { [weak self] _ in
            guard let self else { return }
            self.refresh(Set(self.expanded))
        })
    }

    // MARK: Roots

    private func rootsChanged() {
        titleLabel.text = model.roots.count > 1 ? "WORKSPACE" : "FOLDERS"
        rebuild()
        // Roots come in before the reveal that follows them; a root that
        // was cached already shows its remembered expansion.
        for root in model.roots where root.children == nil { load(root) }
        if let selectedURL { select(selectedURL) }
    }

    // MARK: Rows

    private func rebuild() {
        var flat: [Row] = []
        func add(_ node: FileNode, depth: Int, isRoot: Bool) {
            flat.append(Row(node: node, depth: depth, isRoot: isRoot))
            guard expanded.contains(node.url), let children = node.children else { return }
            for child in children { add(child, depth: depth + 1, isRoot: false) }
        }
        for root in model.roots {
            if !expanded.contains(root.url) && root.children != nil && model.roots.count == 1 { expanded.insert(root.url) }
            add(root, depth: 0, isRoot: true)
        }
        rows = flat

        isSyncing = true
        list.removeAll()
        for (index, row) in flat.enumerated() { list.append(makeRow(row, at: index)) }
        isSyncing = false
        if let selectedURL { select(selectedURL) }
    }

    private func makeRow(_ row: Row, at index: Int) -> ListBoxRow {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        box.marginStart = row.depth * 14

        let url = row.node.url
        let isOpen = expanded.contains(url)
        if loading.contains(url) {
            let spinner = Image(iconName: "content-loading-symbolic")
            spinner.pixelSize = 12
            box.append(spinner)
        } else {
            let toggle = Button(iconName: isOpen ? "pan-down-symbolic" : "pan-end-symbolic")
            toggle.addCSSClass(.flat)
            toggle.addCSSClass("circular")
            toggle.tooltipText = isOpen ? "Collapse \(row.node.name)" : "Expand \(row.node.name)"
            toggle.setAccessibleLabel(isOpen ? "Collapse \(row.node.name)" : "Expand \(row.node.name)")
            toggle.onClicked { [weak self] in self?.toggle(url) }
            box.append(toggle)
        }
        let icon = Image(iconName: row.isRoot ? Self.rootIcon(row.node) : FileIcons.folderSymbolicName(for: url))
        box.append(icon)
        let label = Label(row.node.name)
        label.xalign = 0
        label.hexpand = true
        label.ellipsize = PANGO_ELLIPSIZE_END
        box.append(label)

        let listRow = ListBoxRow()
        listRow.child = box
        listRow.tooltipText = url.path

        let rightClick = GestureClick()
        rightClick.button = 3
        rightClick.onPressed { [weak self, weak listRow] _, x, y in
            guard let self, let listRow else { return }
            self.showMenu(for: url, in: listRow, x: x, y: y)
        }
        listRow.addController(rightClick)
        let middleClick = GestureClick()
        middleClick.button = 2
        middleClick.onPressed { [weak self] _, _, _ in self?.onOpenInNewTab?(url) }
        listRow.addController(middleClick)

        let rowPointer = listRow.pointer
        DragAndDrop.attachSource(to: listRow) { [url] }
        DragAndDrop.attachFileTarget(to: listRow, destination: { url }, highlight: { on in
            let widget = rowPointer.assumingMemoryBound(to: GtkWidget.self)
            if on { gtk_widget_add_css_class(widget, "oneroot-drop-target") } else { gtk_widget_remove_css_class(widget, "oneroot-drop-target") }
        }, drop: { [weak self] urls, folder, move in
            self?.onDrop?(urls, folder, move)
        })
        return listRow
    }

    private static func rootIcon(_ node: FileNode) -> String {
        switch node.kind {
        case DestinationKind.home.nodeKindTag: return "user-home-symbolic"
        case DestinationKind.bootVolume.nodeKindTag, DestinationKind.volume.nodeKindTag: return "drive-harddisk-symbolic"
        case DestinationKind.networkVolume.nodeKindTag, DestinationKind.cloud.nodeKindTag: return "folder-remote-symbolic"
        case DestinationKind.trash.nodeKindTag: return "user-trash-symbolic"
        default: return FileIcons.folderSymbolicName(for: node.url)
        }
    }

    // MARK: Expansion and loading

    private func node(for url: URL) -> FileNode? {
        rows.first { $0.node.url == url }?.node ?? Self.find(url, in: model.roots)
    }

    private static func find(_ url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.url == url { return node }
            if let found = find(url, in: node.children ?? []) { return found }
        }
        return nil
    }

    /// Collapses everything below each root; the roots stay open (a collapsed
    /// root would leave the pane with one row).
    private func collapseAll() {
        expanded = expanded.intersection(Set(model.roots.map(\.url)))
        rebuild()
    }

    /// Opens each root one level. Not recursive: a root can be a whole
    /// volume.
    private func expandTopLevel() {
        for root in model.roots {
            expanded.insert(root.url)
            if root.children == nil { load(root) }
        }
        rebuild()
    }

    private func toggle(_ url: URL) {
        if expanded.contains(url) {
            expanded.remove(url)
            rebuild()
        } else {
            expanded.insert(url)
            if let node = node(for: url), node.children == nil { load(node) } else { rebuild() }
        }
    }

    /// Reads a folder's subfolders off the main thread (the view model does)
    /// and shows them; a stale answer for a node that's gone is dropped.
    @discardableResult
    private func load(_ node: FileNode, then completion: (() -> Void)? = nil) -> Task<Void, Never> {
        loading.insert(node.url)
        rebuild()
        return Task { [weak self] in
            guard let self else { return }
            let children = await self.model.children(of: node)
            let visible = self.showsHidden() ? children : children.filter { !$0.name.hasPrefix(".") }
            node.children = visible.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.loading.remove(node.url)
            self.rebuild()
            completion?()
        }
    }

    /// Re-reads the already-loaded folders among `urls` (the file watcher
    /// or View ▸ Reload). Folders never opened stay unread.
    private func refresh(_ urls: Set<URL>) {
        model.refreshRequests.subtract(urls)
        for url in urls {
            guard let node = node(for: url), node.children != nil, !loading.contains(url) else { continue }
            Task { [weak self] in
                guard let self else { return }
                let children = await self.model.children(of: node)
                let visible = self.showsHidden() ? children : children.filter { !$0.name.hasPrefix(".") }
                node.children = visible.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.rebuild()
            }
        }
    }

    // MARK: Reveal

    /// Opens the path down to `url` inside whichever root contains it and
    /// selects it, scrolling it into view.
    private func reveal(_ url: URL) {
        selectedURL = url
        guard let root = model.roots.first(where: { Self.isInside(url, root: $0.url) }) else {
            list.unselectAll()
            return
        }
        expandPath(from: root, to: url)
    }

    private func expandPath(from node: FileNode, to target: URL) {
        expanded.insert(node.url)
        guard node.children != nil else {
            load(node) { [weak self] in self?.expandPath(from: node, to: target) }
            return
        }
        rebuild()
        guard node.url.standardizedFileURL.path != target.standardizedFileURL.path else { return }
        if let next = node.children?.first(where: { Self.isInside(target, root: $0.url) }) {
            expandPath(from: next, to: target)
        }
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    private func select(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard let index = rows.firstIndex(where: { $0.node.url.standardizedFileURL.path == path }) else {
            isSyncing = true
            list.unselectAll()
            isSyncing = false
            return
        }
        isSyncing = true
        list.selectRow(at: index)
        isSyncing = false
    }

    // MARK: Menu

    private func showMenu(for url: URL, in row: Widget, x: Double, y: Double) {
        let group = SimpleActionGroup()
        func add(_ name: String, _ handler: @escaping @MainActor () -> Void) {
            group.addAction(SimpleAction(name: name, handler: handler))
        }
        add("open") { [weak self] in self?.onNavigate?(url) }
        add("open-tab") { [weak self] in self?.onOpenInNewTab?(url) }
        add("copy-path") { [weak self] in self?.onCopyPath?(url) }
        add("reload") { [weak self] in
            guard let self else { return }
            self.model.refreshRequests.insert(url)
        }
        row.insertActionGroup("tree", group)

        let items = GMenuRef()
        items.append("Open", action: "tree.open")
        items.append("Open in New Tab", action: "tree.open-tab")
        let other = GMenuRef()
        other.append("Copy Path", action: "tree.copy-path")
        other.append("Reload", action: "tree.reload")
        items.appendSection(nil, section: other)
        menu?.unparent()
        guard let raw = gtk_popover_menu_new_from_model_full(items.menuModelPointer, GTK_POPOVER_MENU_NESTED) else { return }
        let object = UnsafeMutableRawPointer(raw)
        g_object_ref_sink(object)
        let popover = PopoverMenu(borrowing: object)
        g_object_unref(object)
        popover.hasArrow = false
        popover.halign = GTK_ALIGN_START
        popover.setParent(row)
        popover.setPointingTo(x: Int(x), y: Int(y))
        _ = popover.popup()
        menu = popover
    }
}
