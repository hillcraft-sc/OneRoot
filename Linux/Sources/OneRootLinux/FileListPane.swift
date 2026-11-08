import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// One pane's file list: a GTK ColumnView over a `FileListViewModel` — the
/// Linux counterpart of the Mac's NSTableView. The view model does the
/// listing, sorting, grouping and filtering; this shows `items` and sends
/// back selection, sorting and opening.
///
/// The list model holds one placeholder object per row and the rows
/// themselves live in `rows` (GTK only binds what's on screen).
@MainActor
final class FileListPane {
    enum Row {
        case group(String)
        case node(FileNode)

        var node: FileNode? {
            if case .node(let node) = self { return node }
            return nil
        }
    }

    let viewModel: FileListViewModel
    /// What a parent puts in its layout.
    let widget: Box

    /// Opening a file (not a folder): the window decides how.
    var onOpenFile: ((FileNode) -> Void)?
    /// A right-click: the rows it applies to are selected first.
    var onContextMenu: ((Double, Double) -> Void)?
    /// Search Subfolders: this folder's filter, for Advanced Search.
    var onSearchSubfolders: ((SearchCriteria) -> Void)? {
        get { filterBar.onSearchSubfolders }
        set { filterBar.onSearchSubfolders = newValue }
    }
    /// Any click or key press in the list: this pane now has the focus.
    var onFocus: (() -> Void)?

    let filterBar: FilterBar
    private let flatViewBar: FlatViewBar
    private(set) var rows: [Row] = []
    let columnView: ColumnView
    /// The Grid view: the same rows and selection, shown as icons.
    private(set) var gridView: GridView!
    private var gridFactory: SignalListItemFactory?
    /// Icon edge in Grid view, in pixels.
    static var gridIconSize: Int { GridIconSize.shared.size }
    private let store = ListStore()
    private let selection: MultiSelection
    private let stack = Stack()
    private let emptyPage = StatusPage()
    private var columns: [(field: FileColumn, column: ColumnViewColumn)] = []
    private var sorterObject: GObjectRef?
    private var watches: [ObservationWatch] = []
    private var isSyncingSelection = false
    /// Which row each on-screen cell shows (cells are recycled).
    var cellPositions: [UnsafeMutableRawPointer: Int] = [:]
    private var cellHandledRightClick = false
    private var menu: PopoverMenu?
    /// Items the view model asked to select (a paste, a new folder) that
    /// may not be listed yet: selected when they appear.
    private var pendingSelection: Set<URL>?
    /// Keys the list handles itself (Delete, F2, Backspace, …) — not
    /// app-wide shortcuts, which would take them from text fields.
    var onKey: ((UInt32, GdkModifierType) -> Bool)?
    private var isSyncingSort = false

    init(viewModel: FileListViewModel) {
        self.viewModel = viewModel
        selection = MultiSelection(model: store)
        columnView = ColumnView(model: selection)
        columnView.showColumnSeparators = false
        columnView.showRowSeparators = false
        columnView.enableRubberband = true
        columnView.reorderable = true
        columnView.addCSSClass("oneroot-file-list")
        columnView.setAccessibleLabel("Files")

        let scroller = ScrolledWindow(child: columnView)
        scroller.vexpand = true
        scroller.hexpand = true
        gridView = GridView(model: selection, factory: SignalListItemFactory())
        gridView.addCSSClass("oneroot-file-grid")
        gridView.setAccessibleLabel("Files")
        gtk_grid_view_set_enable_rubberband(gridView.opaquePointer, 1)
        gridView.maxColumns = 24
        let gridScroller = ScrolledWindow(child: gridView)
        gridScroller.vexpand = true
        gridScroller.hexpand = true

        emptyPage.addCSSClass("compact")
        stack.addNamed(scroller, name: "list")
        stack.addNamed(gridScroller, name: "grid")
        stack.addNamed(emptyPage, name: "empty")
        stack.vexpand = true
        stack.hexpand = true

        filterBar = FilterBar(viewModel: viewModel)
        widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        widget.append(filterBar.widget)
        flatViewBar = FlatViewBar(viewModel: viewModel)
        widget.append(flatViewBar.widget)
        widget.append(stack)
        gridFactory = Self.makeGridFactory(self)
        gtk_grid_view_set_factory(gridView.opaquePointer, OpaquePointer(gridFactory!.pointer))
        // A new icon size: a fresh factory, so the cells are made again.
        watches.append(ObservationWatch.watch({ GridIconSize.shared.size }, emitsInitialValue: false) { [weak self] _ in
            guard let self else { return }
            self.gridFactory = Self.makeGridFactory(self)
            gtk_grid_view_set_factory(self.gridView.opaquePointer, OpaquePointer(self.gridFactory!.pointer))
        })

        gridView.onActivate { [weak self] position in self?.activate(position) }
        columnView.onActivate { [weak self] position in self?.activate(position) }
        selection.onSelectionChanged { [weak self] in self?.selectionChanged() }
        connectSorter()
        if let model = gtk_column_view_get_columns(columnView.opaquePointer) {
            SignalHelper.connectUIntUIntUInt(GObjectRef(borrowing: UnsafeMutableRawPointer(model)), signal: .custom("items-changed")) { [weak self] _, _, _ in
                self?.columnsReordered()
            }
        }
        addGestures(to: scroller, view: columnView)
        addGestures(to: gridScroller, view: gridView)
        filterBar.onReturnToList = { [weak self] in self?.focus() }

        watches.append(ObservationWatch.watch({ viewModel.displayedColumns }) { [weak self] columns in
            self?.buildColumns(columns)
        })
        watches.append(ObservationWatch.watch({ (viewModel.items, viewModel.groupBy, viewModel.folderSizes) }) { [weak self] _ in
            self?.reloadRows()
        })
        watches.append(ObservationWatch.watch({ viewModel.viewMode }) { [weak self] _ in
            self?.updateEmptyState()
        })
        watches.append(ObservationWatch.watch({ viewModel.comparisonStatuses }, emitsInitialValue: false) { [weak self] _ in
            self?.reloadRows()
        })
        watches.append(ObservationWatch.watch({ (viewModel.isLoading, viewModel.isPermissionDenied, viewModel.listingErrorMessage, viewModel.items.isEmpty, viewModel.filter.hasFilters) }) { [weak self] _ in
            self?.updateEmptyState()
        })
        watches.append(ObservationWatch.watch({ viewModel.currentLocationURL }, emitsInitialValue: false) { [weak self] _ in
            guard let self, !self.rows.isEmpty else { return }
            self.scrollView(to: 0)
        })
        watches.append(ObservationWatch.watch({ viewModel.selectionRequest }, emitsInitialValue: false) { [weak self] _ in
            guard let self else { return }
            self.pendingSelection = viewModel.requestedSelection
            self.applyPendingSelection()
        })
        watches.append(ObservationWatch.watch({ viewModel.clearSelectionTrigger }, emitsInitialValue: false) { [weak self] _ in
            self?.selection.unselectAll()
        })
        watches.append(ObservationWatch.watch({ (viewModel.sortField, viewModel.sortDirection) }) { [weak self] _ in
            self?.syncSortIndicator()
        })
    }

    var selectedNodes: [FileNode] { viewModel.selectedNodes }

    /// The list or the grid, whichever is showing.
    private var activeView: Widget {
        viewModel.viewMode == .icons ? gridView : columnView
    }

    func focus() {
        _ = activeView.grabFocus()
    }

    private func scrollView(to position: Int, flags: ListScrollFlags = .none) {
        if viewModel.viewMode == .icons {
            gridView.scrollTo(position, flags: flags)
        } else {
            columnView.scrollTo(position, flags: flags)
        }
    }

    private static func makeGridFactory(_ pane: FileListPane) -> SignalListItemFactory {
        let factory = SignalListItemFactory()
        factory.onSetup { [weak pane] item in
            let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 4)
            box.addCSSClass("oneroot-grid-cell")
            let image = Image()
            image.pixelSize = gridIconSize
            let label = Label("")
            label.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            label.widthChars = 14
            label.maxWidthChars = 18
            label.justify = GTK_JUSTIFY_CENTER
            box.append(image)
            box.append(label)
            item.child = box
            if let cell = item.child {
                pane?.addRightClick(to: cell)
                pane?.addDragAndDrop(to: cell)
            }
        }
        factory.onBind { [weak pane] item in
            guard let pane, item.position < pane.rows.count, let child = item.child,
                  let image = child.firstChild?.cast(Image.self),
                  let label = child.lastChild?.cast(Label.self) else { return }
            pane.cellPositions[child.pointer] = item.position
            switch pane.rows[item.position] {
            case .group(let title):
                image.visible = false
                let count = pane.groupItemCount(after: item.position)
                label.markup = "<b>\(escaped(title))</b>  <span alpha=\"65%\">\(count)</span>"
                label.ellipsize = PANGO_ELLIPSIZE_NONE
                label.wrap = true
                child.addCSSClass("oneroot-grid-group")
                child.tooltipText = nil
            case .node(let node):
                child.removeCSSClass("oneroot-grid-group")
                label.wrap = false
                label.ellipsize = PANGO_ELLIPSIZE_MIDDLE
                image.visible = true
                FileIcons.set(image, to: node)
                image.pixelSize = gridIconSize
                label.text = node.name
                label.opacity = node.name.hasPrefix(".") ? 0.6 : 1
                child.tooltipText = node.name
            }
        }
        return factory
    }

    /// How many items follow the group heading at `position`, up to the next heading.
    func groupItemCount(after position: Int) -> Int {
        var count = 0
        for row in rows.dropFirst(position + 1) {
            guard case .node = row else { break }
            count += 1
        }
        return count
    }

    // MARK: Compare Panes

    private static let comparisonClasses = ["oneroot-cmp-only", "oneroot-cmp-newer", "oneroot-cmp-differs"]

    /// Shows or hides the status word at the end of a name cell.
    private func showComparisonStatus(for node: FileNode, in cell: Widget) {
        guard let status = cell.lastChild?.cast(Label.self) else { return }
        for css in Self.comparisonClasses { status.removeCSSClass(css) }
        guard let found = viewModel.comparisonStatuses?[node.name], found != .same else {
            status.visible = false
            status.tooltipText = nil
            return
        }
        status.text = ComparisonText.label(found)
        status.tooltipText = ComparisonText.explanation(found)
        if let css = ComparisonText.cssClass(found) { status.addCSSClass(css) }
        status.visible = true
    }

    // MARK: Columns

    private var isRebuildingColumns = false

    private func buildColumns(_ fields: [FileColumn], force: Bool = false) {
        guard force || fields != displayedOrder() else { return }
        isRebuildingColumns = true
        defer { isRebuildingColumns = false }
        for (_, column) in columns { columnView.removeColumn(column) }
        columns = fields.map { field in (field, makeColumn(field)) }
        for (index, entry) in columns.enumerated() {
            columnView.appendColumn(entry.column)
            let menu = Self.columnsMenu(visible: fields, for: entry.field, position: index)
            gtk_column_view_column_set_header_menu(entry.column.opaquePointer, menu.menuModelPointer)
        }
        syncSortIndicator()
    }

    /// Right-click on a column header: show or hide a column. (A "\u{2713}"
    /// marks the shown ones; Name can't be hidden and isn't listed.)
    static func columnsMenu(visible: [FileColumn], for field: FileColumn, position: Int) -> GMenuRef {
        let menu = GMenuRef()
        // Moving a column by menu, for where dragging a header doesn't work.
        let moves = GMenuRef()
        if position > 1 {
            let left = GMenuItemRef(label: "Move Left", action: "win.move-column")
            left.setTargetValue(Variant.string("\(field.rawValue):-1"))
            moves.appendItem(left)
        }
        if position > 0 && position < visible.count - 1 {
            let right = GMenuItemRef(label: "Move Right", action: "win.move-column")
            right.setTargetValue(Variant.string("\(field.rawValue):1"))
            moves.appendItem(right)
        }
        menu.appendSection(nil, section: moves)
        let toggles = GMenuRef()
        for column in FileColumn.allCases where column.isRemovable && column != .location {
            let shown = visible.contains(column)
            let item = GMenuItemRef(label: (shown ? "\u{2713} " : "") + column.title, action: "win.toggle-column")
            item.setTargetValue(Variant.string(column.rawValue))
            toggles.appendItem(item)
        }
        menu.appendSection(nil, section: toggles)
        return menu
    }

    /// The columns in the order the view shows them (after a drag).
    private func displayedOrder() -> [FileColumn] {
        guard let model = gtk_column_view_get_columns(columnView.opaquePointer) else { return columns.map(\.field) }
        var order: [FileColumn] = []
        for index in 0..<g_list_model_get_n_items(model) {
            guard let item = g_list_model_get_item(model, index) else { continue }
            defer { g_object_unref(item) }
            if let match = columns.first(where: { UnsafeMutableRawPointer($0.column.opaquePointer) == item }) {
                order.append(match.field)
            }
        }
        return order
    }

    /// A header was dragged to a new place: remember the order. Name stays
    /// first; if the saved order ends up unchanged the view is put back.
    private func columnsReordered() {
        guard !isRebuildingColumns else { return }
        // GTK moves a column as remove + insert: wait until it has settled.
        MainContext.task { [weak self] in self?.applyColumnOrder() }
    }

    private func applyColumnOrder() {
        guard !isRebuildingColumns else { return }
        let order = displayedOrder()
        guard order.count == columns.count, !order.isEmpty, order != viewModel.displayedColumns else { return }
        viewModel.reorderColumns(order)
        let wanted = viewModel.displayedColumns
        if wanted != order { buildColumns(wanted, force: true) }
    }

    /// Moves a column one place (Name stays first).
    func moveColumn(_ field: FileColumn, by offset: Int) {
        var order = displayedOrder()
        guard let index = order.firstIndex(of: field), field != .name else { return }
        let target = index + offset
        guard target >= 1, target < order.count else { return }
        order.swapAt(index, target)
        viewModel.reorderColumns(order)
        if viewModel.displayedColumns != displayedOrder() { buildColumns(viewModel.displayedColumns, force: true) }
    }

    func toggleColumn(_ field: FileColumn) {
        viewModel.toggleColumn(field)
    }

    private func makeColumn(_ field: FileColumn) -> ColumnViewColumn {
        let factory = SignalListItemFactory()
        factory.onSetup { [weak self] item in
            defer {
                if let cell = item.child {
                    self?.addRightClick(to: cell)
                    self?.addDragAndDrop(to: cell)
                }
            }
            if field == .name {
                let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
                let image = Image()
                image.pixelSize = 16
                let label = Label("")
                label.xalign = 0
                label.ellipsize = PANGO_ELLIPSIZE_MIDDLE
                label.widthChars = 12
                label.hexpand = true
                box.append(image)
                box.append(label)
                // Compare Panes: the item's status, as a word.
                let status = Label("")
                status.addCSSClass("caption")
                status.visible = false
                box.append(status)
                item.child = box
            } else {
                let label = Label("")
                label.xalign = field == .size ? 1 : 0
                label.ellipsize = PANGO_ELLIPSIZE_END
                label.addCSSClass(.dimLabel)
                if field == .size { label.addCSSClass("numeric") }
                item.child = label
            }
        }
        factory.onBind { [weak self] item in
            guard let self, item.position < self.rows.count, let child = item.child else { return }
            let row = self.rows[item.position]
            self.cellPositions[child.pointer] = item.position
            if field == .name {
                guard let image = child.firstChild?.cast(Image.self), let label = child.firstChild?.nextSibling?.cast(Label.self) else { return }
                switch row {
                case .group(let title):
                    image.visible = false
                    if let status = child.lastChild?.cast(Label.self) { status.visible = false }
                    label.markup = "<b>\(Self.escaped(title))</b>"
                case .node(let node):
                    image.visible = true
                    FileIcons.set(image, to: node)
                    label.text = node.name
                    label.opacity = node.name.hasPrefix(".") ? 0.6 : 1
                    self.showComparisonStatus(for: node, in: child)
                }
            } else {
                let label = child.cast(Label.self)
                label.text = row.node.map { Formatting.cell($0, field, folderSizes: self.viewModel.folderSizes) } ?? ""
            }
        }
        let column = ColumnViewColumn(title: field.title, factory: factory)
        column.resizable = true
        if field == .name {
            column.expand = true
        } else {
            column.fixedWidth = ColumnWidthStore.shared.width(for: field) ?? Int(field.defaultWidth)
            // Remember a width the user drags to (not our own setting of it).
            let changed: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { object, _, data in
                guard let object, let data else { return }
                let width = Int(gtk_column_view_column_get_fixed_width(OpaquePointer(object)))
                let raw = Unmanaged<NSString>.fromOpaque(data).takeUnretainedValue() as String
                guard width > 0, let field = FileColumn(rawValue: raw) else { return }
                MainActor.assumeIsolated { ColumnWidthStore.shared.set(width, for: field) }
            }
            let free: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
                if let data { Unmanaged<NSString>.fromOpaque(data).release() }
            }
            g_signal_connect_data(UnsafeMutableRawPointer(column.opaquePointer), "notify::fixed-width",
                                  unsafeBitCast(changed, to: GCallback.self),
                                  Unmanaged.passRetained(field.rawValue as NSString).toOpaque(),
                                  unsafeBitCast(free, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        }
        // A sorter that sorts nothing: it makes the header clickable and
        // shows the arrow; the view model does the sorting.
        if let sorter = UnsafeMutableRawPointer(gtk_custom_sorter_new(nil, nil, nil)) {
            gtk_column_view_column_set_sorter(column.opaquePointer, sorter.assumingMemoryBound(to: GtkSorter.self))
            g_object_unref(sorter)
        }
        return column
    }

    static func escaped(_ text: String) -> String {
        guard let escaped = g_markup_escape_text(text, -1) else { return text }
        defer { g_free(escaped) }
        return String(cString: escaped)
    }

    // MARK: Sorting

    private var columnViewSorter: OpaquePointer? {
        gtk_column_view_get_sorter(columnView.opaquePointer).map { OpaquePointer($0) }
    }

    private func connectSorter() {
        guard let sorter = columnViewSorter else { return }
        let object = GObjectRef(borrowing: UnsafeMutableRawPointer(sorter))
        sorterObject = object
        // "changed" passes a GtkSorterChange: the one-integer form.
        SignalHelper.connectUInt(object, signal: .custom("changed")) { [weak self] _ in
            self?.sortChanged()
        }
    }

    private func sortChanged() {
        guard !isSyncingSort, let sorter = columnViewSorter,
              let primary = gtk_column_view_sorter_get_primary_sort_column(sorter),
              let field = columns.first(where: { $0.column.opaquePointer == primary })?.field else { return }
        let ascending = gtk_column_view_sorter_get_primary_sort_order(sorter) == GTK_SORT_ASCENDING
        if field != viewModel.sortField || ascending != (viewModel.sortDirection == .ascending) {
            viewModel.setSort(field: field)
        }
        syncSortIndicator()
    }

    private func syncSortIndicator() {
        guard let column = columns.first(where: { $0.field == viewModel.sortField })?.column else { return }
        isSyncingSort = true
        defer { isSyncingSort = false }
        gtk_column_view_sort_by_column(columnView.opaquePointer, column.opaquePointer,
                                       viewModel.sortDirection == .ascending ? GTK_SORT_ASCENDING : GTK_SORT_DESCENDING)
    }

    // MARK: Rows

    private func reloadRows() {
        rows = Self.rows(for: viewModel.items, groupedBy: viewModel.groupBy)
        let removed = UInt32(store.count)
        var placeholders: [gpointer?] = rows.map { _ in cadw_object_new(cadw_type_object()) }
        isSyncingSelection = true
        placeholders.withUnsafeMutableBufferPointer { buffer in
            g_list_store_splice(store.opaquePointer, 0, removed, buffer.baseAddress, UInt32(buffer.count))
        }
        for object in placeholders { g_object_unref(object) }
        isSyncingSelection = false
        if pendingSelection != nil {
            applyPendingSelection()
        } else {
            select(urls: Set(viewModel.selectedNodes.map(\.url)), scroll: false)
        }
        selectionChanged()
    }

    private func applyPendingSelection() {
        guard let wanted = pendingSelection else { return }
        let listed = Set(rows.compactMap { $0.node?.url.standardizedFileURL })
        let found = wanted.filter { listed.contains($0.standardizedFileURL) }
        guard !found.isEmpty else { return }
        select(urls: found, scroll: true)
        selectionChanged()
        if found.count == wanted.count { pendingSelection = nil }
    }

    static func rows(for items: [FileNode], groupedBy field: FileColumn?) -> [Row] {
        guard let field else { return items.map(Row.node) }
        var rows: [Row] = []
        var current: String?
        for node in items {
            let label = FileGrouping.group(for: node, by: field).label
            if label != current {
                rows.append(.group(label))
                current = label
            }
            rows.append(.node(node))
        }
        return rows
    }

    private var loadingTask: Task<Void, Never>?

    private func updateEmptyState() {
        let vm = viewModel
        loadingTask?.cancel()
        loadingTask = nil
        if vm.items.isEmpty, vm.isLoading {
            stack.visibleChildName = vm.viewMode == .icons ? "grid" : "list"
            // A visible loading state for a slow folder (a network share, a
            // sleeping disk) without a flash for the usual instant one.
            loadingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self, self.viewModel.isLoading, self.viewModel.items.isEmpty else { return }
                self.emptyPage.iconName = "content-loading-symbolic"
                self.emptyPage.title = "Loading\u{2026}"
                self.emptyPage.description = "Reading this folder."
                self.stack.visibleChildName = "empty"
            }
            return
        }
        guard vm.items.isEmpty else {
            stack.visibleChildName = vm.viewMode == .icons ? "grid" : "list"
            return
        }
        if vm.isPermissionDenied {
            emptyPage.iconName = "action-unavailable-symbolic"
            emptyPage.title = "No Permission"
            emptyPage.description = "You don't have permission to see what's in this folder."
        } else if let message = vm.listingErrorMessage {
            emptyPage.iconName = "dialog-warning-symbolic"
            emptyPage.title = "Can't Open This Folder"
            emptyPage.description = message
        } else if vm.filter.hasFilters {
            emptyPage.iconName = "edit-find-symbolic"
            emptyPage.title = "No Matches"
            emptyPage.description = "Nothing in this folder matches the filter."
        } else {
            emptyPage.iconName = "folder-symbolic"
            emptyPage.title = "Empty Folder"
            emptyPage.description = nil
        }
        stack.visibleChildName = "empty"
    }

    /// Switches between List and Grid (remembered per folder).
    func setViewMode(_ mode: FileViewMode) {
        viewModel.setViewMode(mode)
    }

    // MARK: Selection

    private var selectionModel: OpaquePointer { selection.opaquePointer }

    private func selectionChanged() {
        guard !isSyncingSelection else { return }
        let bitset = gtk_selection_model_get_selection(selectionModel)
        defer { gtk_bitset_unref(bitset) }
        let count = gtk_bitset_get_size(bitset)
        var nodes: [FileNode] = []
        nodes.reserveCapacity(Int(count))
        for index in 0..<count {
            let position = Int(gtk_bitset_get_nth(bitset, UInt32(index)))
            if position < rows.count, let node = rows[position].node { nodes.append(node) }
        }
        if nodes.map(\.url) != viewModel.selectedNodes.map(\.url) {
            viewModel.updateSelection(nodes)
        }
    }

    func select(urls: Set<URL>, scroll: Bool) {
        let wanted = Set(urls.map(\.standardizedFileURL))
        let selected = gtk_bitset_new_empty()
        var first: Int?
        for (position, row) in rows.enumerated() {
            if let node = row.node, wanted.contains(node.url.standardizedFileURL) {
                gtk_bitset_add(selected, UInt32(position))
                if first == nil { first = position }
            }
        }
        let mask = gtk_bitset_new_range(0, UInt32(rows.count))
        isSyncingSelection = true
        gtk_selection_model_set_selection(selectionModel, selected, mask)
        isSyncingSelection = false
        gtk_bitset_unref(selected)
        gtk_bitset_unref(mask)
        if scroll, let first {
            scrollView(to: first, flags: .focus)
        }
    }

    func selectAll() {
        selection.selectAll()
    }

    func deselectAll() {
        gtk_selection_model_unselect_all(selectionModel)
    }

    // MARK: Type to select

    private var typing = TypeToSelect()

    /// A typed letter jumps to the first name starting with what was typed
    /// in the last second. Returns whether it was used.
    func typeSelect(_ character: Character) -> Bool {
        let prefix = typing.type(character)
        let names = rows.map { $0.node?.name ?? "" }
        let current = viewModel.selectedNodes.count == 1
            ? rows.firstIndex { $0.node?.url == viewModel.selectedNodes[0].url } : nil
        guard let position = TypeToSelect.match(prefix: prefix, in: names, current: current),
              let node = rows[position].node else {
            return true
        }
        select(urls: [node.url], scroll: true)
        return true
    }

    // MARK: Opening

    private func activate(_ position: Int) {
        guard position < rows.count, let node = rows[position].node else { return }
        if node.isNavigable(browsePackage: false) {
            viewModel.navigate(to: node.url)
        } else {
            onOpenFile?(node)
        }
    }

    /// Opens what's selected: a folder in place, files with their apps.
    func openSelection() {
        let nodes = viewModel.selectedNodes
        if nodes.count == 1, let node = nodes.first, node.isNavigable(browsePackage: false) {
            viewModel.navigate(to: node.url)
            return
        }
        for node in nodes where !node.isDirectory { onOpenFile?(node) }
    }

    /// Shows a menu at a point in the list (a right-click).
    func showMenu(_ model: GMenuRef, x: Double, y: Double) {
        menu?.unparent()
        // Nested: submenus (Open With) open beside the menu, so the menu
        // keeps its own height instead of sliding pages.
        guard let raw = gtk_popover_menu_new_from_model_full(model.menuModelPointer, GTK_POPOVER_MENU_NESTED) else { return }
        let object = UnsafeMutableRawPointer(raw)
        g_object_ref_sink(object)
        let popover = PopoverMenu(borrowing: object)
        g_object_unref(object)
        popover.hasArrow = false
        popover.halign = GTK_ALIGN_START
        popover.setParent(activeView)
        popover.setPointingTo(x: Int(x), y: Int(y))
        _ = popover.popup()
        menu = popover
    }

    // MARK: Gestures

    private func addGestures(to scroller: ScrolledWindow, view: Widget) {
        // A right-click on empty space: the folder's own menu.
        let rightClick = GestureClick()
        rightClick.button = 3
        rightClick.onPressed { [weak self] _, x, y in
            guard let self else { return }
            defer { self.cellHandledRightClick = false }
            guard !self.cellHandledRightClick else { return }
            self.onFocus?()
            self.selection.unselectAll()
            self.onContextMenu?(x, y)
        }
        view.addController(rightClick)

        // Files dropped on empty space go into the folder shown.
        let background = scroller.pointer
        DragAndDrop.attachFileTarget(to: scroller, destination: { [weak self] in self?.viewModel.currentDirectory }, highlight: { on in
            let widget = background.assumingMemoryBound(to: GtkWidget.self)
            if on { gtk_widget_add_css_class(widget, "oneroot-drop-background") } else { gtk_widget_remove_css_class(widget, "oneroot-drop-background") }
        }, drop: { [weak self] urls, folder, move in
            self?.viewModel.handleDrop(urls: urls, into: folder, move: move)
        })

        let anyClick = GestureClick()
        anyClick.button = 0
        anyClick.onPressed { [weak self] _, _, _ in self?.onFocus?() }
        gtk_event_controller_set_propagation_phase(OpaquePointer(anyClick.pointer), GTK_PHASE_CAPTURE)
        view.addController(anyClick)

        let focus = EventControllerFocus()
        focus.onEnter { [weak self] in self?.onFocus?() }
        view.addController(focus)

        let keys = EventControllerKey()
        keys.onKeyPressed { [weak self] keyval, _, modifiers in
            self?.onKey?(keyval, modifiers) ?? false
        }
        gtk_event_controller_set_propagation_phase(OpaquePointer(keys.pointer), GTK_PHASE_CAPTURE)
        view.addController(keys)
    }

    /// Dragging rows out (the selection goes along, as in any file manager)
    /// and dropping files onto a folder row — or onto any other row, which
    /// means "into this folder".
    func addDragAndDrop(to cell: Widget) {
        let cellPointer = cell.pointer
        DragAndDrop.attachSource(to: cell) { [weak self] in
            guard let self, let position = self.cellPositions[cellPointer], position < self.rows.count,
                  self.rows[position].node != nil else { return [] }
            self.onFocus?()
            if !self.selection.isSelected(position: position) {
                self.selection.selectItem(position: position, unselectRest: true)
            }
            return self.viewModel.selectedNodes.map(\.url)
        }
        DragAndDrop.attachFileTarget(to: cell, destination: { [weak self] in
            guard let self else { return nil }
            if let position = self.cellPositions[cellPointer], position < self.rows.count,
               let node = self.rows[position].node, node.isNavigable(browsePackage: false) {
                return node.url
            }
            return self.viewModel.currentDirectory
        }, highlight: { [weak self] on in
            guard let self, let position = self.cellPositions[cellPointer], position < self.rows.count,
                  let node = self.rows[position].node, node.isDirectory else { return }
            let widget = cellPointer.assumingMemoryBound(to: GtkWidget.self)
            if on { gtk_widget_add_css_class(widget, "oneroot-drop-target") } else { gtk_widget_remove_css_class(widget, "oneroot-drop-target") }
        }, drop: { [weak self] urls, folder, move in
            self?.viewModel.handleDrop(urls: urls, into: folder, move: move)
        })
    }

    /// Each cell's own right-click: the row becomes the selection unless
    /// it's already part of it (as in every file manager), then the menu.
    func addRightClick(to cell: Widget) {
        // The cell's pointer, not its wrapper: `item.child` hands out a new
        // wrapper each time, which a weak capture would lose at once.
        let cellPointer = cell.pointer
        let click = GestureClick()
        click.button = 3
        click.onPressed { [weak self] _, x, y in
            guard let self, let position = self.cellPositions[cellPointer] else { return }
            self.cellHandledRightClick = true
            self.onFocus?()
            if position < self.rows.count, self.rows[position].node != nil, !self.selection.isSelected(position: position) {
                self.selection.selectItem(position: position, unselectRest: true)
            }
            var point = graphene_point_t(x: Float(x), y: Float(y))
            var converted = graphene_point_t()
            _ = gtk_widget_compute_point(cellPointer.assumingMemoryBound(to: GtkWidget.self), self.activeView.widgetPointer, &point, &converted)
            self.onContextMenu?(Double(converted.x), Double(converted.y))
        }
        cell.addController(click)
    }
}
