import AppKit
import Combine
import QuickLookUI

/// Adds keyboard behavior `NSTableView` doesn't provide out of the box —
/// Return to rename, Delete to trash, Space for Quick Look, ⌘O, the
/// standard Cmd+C/X/V — by handing keys and edit actions to the shared
/// `FileItemActions`. Also points the Quick Look panel at it, since
/// QuickLookUI finds the panel's data source by walking the responder
/// chain from the key window's first responder.
final class FileTableView: NSTableView {
    weak var actions: FileItemActions?

    override func keyDown(with event: NSEvent) {
        if actions?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // Deferred: focus can move mid SwiftUI update (e.g. Quick Look making
        // this first responder), and `onFocus` publishes on the `Tab`.
        if became, let onFocus = actions?.onFocus {
            DispatchQueue.main.async { onFocus() }
        }
        return became
    }

    @objc func copy(_ sender: Any?) { actions?.handleCopy() }
    @objc func cut(_ sender: Any?) { actions?.handleCut() }
    @objc func paste(_ sender: Any?) { actions?.handlePaste() }

    // Edit ▸ Undo/Redo act on file operations while the list has focus —
    // see `FileUndoCenter`.
    @objc func undo(_ sender: Any?) { FileUndoCenter.shared.undo() }
    @objc func redo(_ sender: Any?) { FileUndoCenter.shared.redo() }

    /// Manually drives the context menu instead of relying on AppKit's
    /// automatic `view.menu` popup path — on this environment that
    /// automatic path was failing to display anything at all (AppKit
    /// itself logged `Connection with remote prompt field terminated
    /// (com.apple.ViewBridge.error error 18)` on every right-click, on
    /// both this table and the sidebar's outline view).
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        actions?.isBackgroundRightClick = clickedRow < 0
        if clickedRow >= 0, !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        guard let menu else {
            super.rightMouseDown(with: event)
            return
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = actions
        panel.delegate = actions
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension FileTableView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        FileUndoCenter.shared.validate(menuItem) ?? true
    }
}

/// Right-clicking a column header shows a checklist of columns to toggle.
/// Uses the same manual `popUp` approach as `FileTableView.rightMouseDown`
/// above — this environment's automatic `view.menu` right-click path
/// doesn't reliably show anything for these table/outline views.
final class FileTableHeaderView: NSTableHeaderView {
    /// The theme's bar color, painted behind the cells and in the empty
    /// space past the last column; `nil` leaves AppKit's own header alone.
    var barColor: NSColor?

    override func draw(_ dirtyRect: NSRect) {
        if let barColor {
            barColor.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else {
            super.rightMouseDown(with: event)
            return
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
}

/// One row in the table. Plain rows mirror `items` 1:1; `.header` rows are
/// inserted between them when "Arrange By" grouping is active — see
/// `FileGrouping` for how nodes are bucketed and `rebuildDisplayRows`.
private enum DisplayRow {
    case header(String)
    case item(FileNode)
}

/// Owns the `NSTableView`: columns, cells, sorting, grouping, row-based drag
/// and drop. What you can *do* to the selection (menus, keys, Quick Look,
/// double-click) lives in the shared `actions` (`FileItemActions`), which
/// the icon view uses too. Intent flows out through closures set by
/// `FileListView`; this controller never talks to services or view models
/// directly — it just reports what the user asked for and lets the
/// ViewModel decide how to do it.
@MainActor
final class FileTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let tableView: FileTableView

    /// `reloadData()` clears the table's selection by default, and `items`
    /// gets reassigned on every live-refresh tick from `FileWatcher` — not
    /// just when the user navigates. Without this, any background
    /// filesystem activity (Spotlight, iCloud, a stray `.DS_Store` write)
    /// could silently drop the user's selection out from under them between
    /// clicking a file and acting on it.
    var items: [FileNode] = [] {
        willSet {
            selectionURLsBeforeReload = Set(selectedNodes.map(\.url))
        }
        didSet {
            // `FileListView.updateNSView` assigns this on every SwiftUI
            // update, including ones that have nothing to do with the
            // listing (a selection or loading-state change). Only a real
            // new listing needs the reload.
            guard !Self.isSameListing(oldValue, items) else { return }
            rebuildDisplayRows()
            tableView.reloadData()
            restoreSelectionIfNeeded()
        }
    }
    private var selectionURLsBeforeReload: Set<URL> = []

    /// Same nodes, same order — by identity: every listing from disk makes
    /// new `FileNode`s, so a refresh still counts as new.
    static func isSameListing(_ lhs: [FileNode], _ rhs: [FileNode]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    /// Last `FileListViewModel.quickLookTrigger` value this controller has
    /// already acted on — see `handleQuickLook()`.
    var lastHandledQuickLookTrigger = 0

    /// Which field (if any) `items` are currently bucketed by — `nil` means
    /// no section headers. `items` is expected to already be sorted so that
    /// same-group nodes are contiguous (`FileListViewModel` guarantees
    /// this); this controller only needs to know where to draw the header
    /// boundaries.
    var groupBy: FileColumn? = nil {
        didSet {
            guard oldValue != groupBy else { return }
            rebuildDisplayRows()
            tableView.reloadData()
        }
    }
    private var displayRows: [DisplayRow] = []

    /// Folder sizes worked out so far, and folders still being sized — see
    /// `FileListViewModel.folderSizes`. Only the Size column redraws when
    /// these change, not the whole table.
    var folderSizes: [URL: Int64] = [:] {
        didSet { if oldValue != folderSizes { reloadSizeColumn() } }
    }
    var calculatingFolderSizes: Set<URL> = [] {
        didSet { if oldValue != calculatingFolderSizes { reloadSizeColumn() } }
    }

    /// Compare Panes: each row's status against the other pane, shown at
    /// the end of the Name cell.
    var comparisonStatuses: [String: ComparisonStatus]? {
        didSet { if oldValue != comparisonStatuses { reloadNameColumn() } }
    }

    private func reloadNameColumn() {
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(FileColumn.name.rawValue))
        guard column >= 0, tableView.numberOfRows > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows), columnIndexes: IndexSet(integer: column))
    }

    private static let comparisonBadgeID = NSUserInterfaceItemIdentifier("comparisonBadge")

    private func comparisonBadge(in cell: NSTableCellView) -> NSTextField? {
        cell.subviews.first { $0.identifier == Self.comparisonBadgeID } as? NSTextField
    }

    private func reloadSizeColumn() {
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(FileColumn.size.rawValue))
        guard column >= 0, tableView.numberOfRows > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows), columnIndexes: IndexSet(integer: column))
    }

    /// Which columns are shown, left to right. Set from `FileListView` on
    /// every `updateNSView`; only actually rebuilds the table's columns
    /// when the set changes, to avoid clobbering in-progress resizes.
    var visibleColumns: [FileColumn] = FileColumn.defaultVisible {
        didSet {
            guard oldValue != visibleColumns else { return }
            guard !isSyncingAfterDrag else {
                isSyncingAfterDrag = false
                return
            }
            rebuildColumns()
        }
    }
    /// Set right before `visibleColumns` is updated from inside
    /// `handleColumnDidMove` — the table's columns already reflect that
    /// order (the user just dragged them there), so skip the usual
    /// tear-down-and-rebuild for that one assignment.
    private var isSyncingAfterDrag = false
    /// Set right before `updateSortIndicator` assigns `tableView
    /// .sortDescriptors` to reflect a sort chosen from the shortcut
    /// toolbar's Sort menu (rather than a column header click) — that
    /// assignment fires `sortDescriptorsDidChange` same as a real header
    /// click would, so without this guard it would loop straight back
    /// into `onSortChange`.
    private var isSyncingSortDescriptor = false

    /// Menus, keyboard actions, Quick Look, double-click — shared with the
    /// icon view. `FileListView` wires its closures.
    let actions = FileItemActions()

    /// Follows `ThemeStore`; see `apply(_:)`.
    private(set) var theme = ThemeStore.shared.current
    private var themeWatch: ObservationWatch?

    var onSortChange: ((FileColumn) -> Void)?
    var onToggleColumn: ((FileColumn) -> Void)?
    var onReorderColumns: (([FileColumn]) -> Void)?
    var onSelectionChange: (([FileNode]) -> Void)?


    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var selectedNodes: [FileNode] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row < displayRows.count, case .item(let node) = displayRows[row] else { return nil }
            return node
        }
    }

    /// Rebuilds `displayRows` from `items`, inserting a header row wherever
    /// `FileGrouping`'s label changes — `items` is already grouped-
    /// contiguous by `FileListViewModel`, so a label change always means a
    /// new group is starting, never a repeat further down.
    private func rebuildDisplayRows() {
        guard let groupBy else {
            displayRows = items.map { .item($0) }
            return
        }
        var rows: [DisplayRow] = []
        var lastLabel: String?
        for node in items {
            let label = FileGrouping.group(for: node, by: groupBy).label
            if label != lastLabel {
                rows.append(.header(label))
                lastLabel = label
            }
            rows.append(.item(node))
        }
        displayRows = rows
    }

    /// Re-selects whatever was selected before `items` changed (see the
    /// `willSet`/`didSet` above), mapped through the freshly-rebuilt
    /// `displayRows` rather than assuming row index == item index — grouping
    /// makes that assumption false whenever headers are present.
    /// Always sets the selection, even to nothing: `reloadData()` keeps
    /// the old selected row *numbers*, so in a new folder (or after the
    /// selected items were trashed) other rows would show as selected —
    /// and the view model would never hear that the selection changed.
    private func restoreSelectionIfNeeded() {
        let indices = displayRows.enumerated().compactMap { index, row -> Int? in
            guard case .item(let node) = row, selectionURLsBeforeReload.contains(node.url) else { return nil }
            return index
        }
        let wanted = IndexSet(indices)
        if tableView.selectedRowIndexes != wanted {
            tableView.selectRowIndexes(wanted, byExtendingSelection: false)
        }
    }

    /// Set once the first `select(_:)` has run — see `FileListView`.
    var didRestoreInitialSelection = false
    /// Last `FileListViewModel.selectionRequest` acted on.
    var lastHandledSelectionRequest = 0
    /// Last `FileListViewModel.clearSelectionTrigger` acted on.
    var lastHandledClearSelectionTrigger = 0

    /// Deselects everything; the usual selection report tells the view model.
    func clearSelection() {
        tableView.deselectAll(nil)
    }

    /// Selects the rows for `urls` and reports the result — a fresh table
    /// taking over a pane (switching tabs) shows the selection its view
    /// model already had, and the view model learns of anything that's
    /// no longer there.
    func select(_ urls: Set<URL>) {
        selectionURLsBeforeReload = urls
        restoreSelectionIfNeeded()
        if let row = tableView.selectedRowIndexes.first {
            tableView.scrollRowToVisible(row)
        }
        let nodes = selectedNodes
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChange?(nodes)
        }
    }

    override init() {
        let tableView = FileTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.style = .plain
        tableView.floatsGroupRows = true
        tableView.allowsColumnResizing = true
        // Widening a column pushes the rest right (scrolling sideways when
        // they no longer fit), as in Finder. AppKit's default took the
        // width from the last column, which collapsed to its minimum and
        // then left nothing to resize with. Name still fills spare width
        // when the view grows — see `fitNameColumn()`.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = true
        // Roomier than AppKit's default, without losing desktop density.
        tableView.rowHeight = 30

        self.tableView = tableView
        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.every, forLocal: true)
        tableView.setDraggingSourceOperationMask(.every, forLocal: false)

        tableView.actions = actions
        actions.hostView = tableView
        actions.selectionProvider = { [weak self] in self?.selectedNodes ?? [] }

        let menu = NSMenu()
        menu.delegate = actions
        tableView.menu = menu

        let headerView = FileTableHeaderView()
        let columnMenu = NSMenu()
        columnMenu.delegate = self
        headerView.menu = columnMenu
        tableView.headerView = headerView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColumnDidMove),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColumnDidResize),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )

        rebuildColumns()

        let themes = ThemeStore.shared
        themeWatch = ObservationWatch.watch({ themes.current }) { [weak self] theme in
            self?.apply(theme)
        }
    }

    // MARK: Theme

    /// Recolors the list: background, column headers, row selection, and
    /// every cell's text and folder icon.
    private func apply(_ theme: Theme) {
        self.theme = theme
        tableView.backgroundColor = theme.listBackgroundNSColor
        (tableView.headerView as? FileTableHeaderView)?.barColor = theme.surfaces?.bar.nsColor
        for column in tableView.tableColumns {
            (column.headerCell as? ThemedHeaderCell)?.theme = theme
        }
        tableView.headerView?.needsDisplay = true
        tableView.enclosingScrollView?.backgroundColor = theme.listBackgroundNSColor
        // In place, not `reloadData()`, which would drop the selection:
        // recolor the row views that exist and have the cells rebuilt.
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? ThemedRowView)?.selectionColor = theme.selectionNSColor
            rowView.needsDisplay = true
        }
        if tableView.numberOfRows > 0, !tableView.tableColumns.isEmpty {
            tableView.reloadData(
                forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows),
                columnIndexes: IndexSet(integersIn: 0..<tableView.tableColumns.count)
            )
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ThemedRowView()
        rowView.selectionColor = theme.selectionNSColor
        return rowView
    }

    // MARK: Columns

    /// The user dragged a column header to a new position. `.name` can't
    /// move (see `tableView(_:shouldReorderColumn:toColumn:)`), so it's
    /// still first; read the rest back off the table itself since that's
    /// now the source of truth for order.
    @objc private func handleColumnDidMove(_ notification: Notification) {
        let newOrder = tableView.tableColumns.compactMap { FileColumn(rawValue: $0.identifier.rawValue) }
        isSyncingAfterDrag = true
        visibleColumns = newOrder
        onReorderColumns?(newOrder)
    }

    /// Watches `scrollView`'s visible width so Name can fill it — call
    /// once, with the scroll view this table is the document of.
    func attach(to scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        clipView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewFrameChange),
            name: NSView.frameDidChangeNotification,
            object: clipView
        )
    }

    /// Name's width as the user last set it; it only grows past this to
    /// fill the view, and shrinks back to it when the view narrows.
    private var nameBaseWidth = FileColumn.name.defaultWidth
    /// Set while `fitNameColumn()` resizes Name, so that isn't mistaken
    /// for the user's own resize.
    private var isFittingName = false

    @objc private func handleColumnDidResize(_ notification: Notification) {
        guard !isFittingName,
              let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              column.identifier.rawValue == FileColumn.name.rawValue else { return }
        nameBaseWidth = column.width
    }

    @objc private func handleClipViewFrameChange(_ notification: Notification) {
        fitNameColumn()
    }

    /// Widens Name to take up whatever room the other columns leave in
    /// the visible width, never narrower than the user's own width.
    private func fitNameColumn() {
        guard let clipView = tableView.enclosingScrollView?.contentView,
              let name = tableView.tableColumns.first(where: { $0.identifier.rawValue == FileColumn.name.rawValue }) else { return }
        let others = tableView.tableColumns.filter { $0 !== name }.reduce(CGFloat(0)) { $0 + $1.width }
        let spacing = tableView.intercellSpacing.width * CGFloat(tableView.tableColumns.count)
        let fill = floor(clipView.bounds.width - others - spacing)
        let width = max(nameBaseWidth, fill, name.minWidth)
        guard abs(name.width - width) >= 1 else { return }
        isFittingName = true
        name.width = width
        isFittingName = false
    }

    /// Tears down and re-adds `NSTableColumn`s to match `visibleColumns`,
    /// preserving the width of every column that stays visible — Name
    /// included: showing or hiding another column leaves it as it is.
    /// Name is fitted to the view only the first time, and when the view
    /// itself changes size.
    private func rebuildColumns() {
        let isFirstBuild = tableView.tableColumns.isEmpty
        let existingWidths = Dictionary(uniqueKeysWithValues: tableView.tableColumns.map { ($0.identifier.rawValue, $0.width) })
        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }
        for fileColumn in visibleColumns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(fileColumn.rawValue))
            let headerCell = ThemedHeaderCell(textCell: fileColumn.title)
            headerCell.theme = theme
            column.headerCell = headerCell
            column.title = fileColumn.title
            column.width = existingWidths[fileColumn.rawValue] ?? fileColumn.defaultWidth
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: fileColumn.rawValue, ascending: true)
            tableView.addTableColumn(column)
        }
        if isFirstBuild { fitNameColumn() }
        tableView.reloadData()
    }

    private func rebuildColumnMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for column in FileColumn.allCases {
            let item = NSMenuItem(title: column.title, action: #selector(handleToggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column
            item.state = visibleColumns.contains(column) ? .on : .off
            item.isEnabled = column.isRemovable
            menu.addItem(item)
        }
    }

    @objc private func handleToggleColumn(_ sender: NSMenuItem) {
        guard let column = sender.representedObject as? FileColumn else { return }
        onToggleColumn?(column)
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayRows.count
    }

    /// `.name` is always the leftmost column and can't be dragged out of
    /// place, and nothing else can be dropped ahead of it.
    func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        columnIndex != 0 && newColumnIndex != 0
    }

    /// Section headers are informational, not selectable — matches how
    /// Finder's own "Arrange By" group rows behave.
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard row < displayRows.count, case .header = displayRows[row] else { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < displayRows.count, case .item = displayRows[row] else { return false }
        return true
    }

    /// `reloadData()` and `selectRowIndexes(_:)` both fire this synchronously
    /// — including when called from `items`'s `didSet`, which itself runs
    /// from `FileListView.updateNSView` while SwiftUI is mid-update. Calling
    /// `onSelectionChange` (which publishes an `@Published` change on the
    /// view model) synchronously from there is "publishing changes from
    /// within view updates," which SwiftUI does not tolerate — it caused a
    /// hang/crash on every navigation. Deferring the callback to the next
    /// run loop tick lets the current update finish first.
    func tableViewSelectionDidChange(_ notification: Notification) {
        let nodes = selectedNodes
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChange?(nodes)
        }
    }

    private func node(atRow row: Int) -> FileNode? {
        guard row >= 0, row < displayRows.count, case .item(let node) = displayRows[row] else { return nil }
        return node
    }

    // MARK: Drag source

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        node(atRow: row)?.url as NSURL?
    }

    // MARK: Drop destination

    private func dropTargetNode(forRow row: Int, dropOperation: NSTableView.DropOperation) -> FileNode? {
        guard dropOperation == .on, let node = node(atRow: row), node.isDirectory else { return nil }
        return node
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let urls = info.draggedFileURLs else { return [] }
        if let targetNode = dropTargetNode(forRow: row, dropOperation: dropOperation), !isValidDropTarget(targetNode.url, for: urls) {
            return []
        }
        return DropActionMenu.operation(for: info)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggedFileURLs else { return false }
        let targetNode = dropTargetNode(forRow: row, dropOperation: dropOperation)
        if let targetNode, !isValidDropTarget(targetNode.url, for: urls) { return false }
        actions.drop(urls, on: targetNode, info: info)
        return true
    }

    /// Group headers span the full row width, so AppKit calls this once
    /// with `tableColumn == nil` for them instead of once per column.
    private func groupHeaderView(_ tableView: NSTableView, title: String) -> NSView {
        let reuseID = NSUserInterfaceItemIdentifier("groupHeader")
        let cell: NSTableCellView
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: reuseID, owner: self) as? NSTableCellView,
           let reusedField = reused.textField {
            cell = reused
            textField = reusedField
        } else {
            cell = NSTableCellView()
            cell.identifier = reuseID
            textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        textField.stringValue = title
        textField.textColor = theme.secondaryTextNSColor
        return cell
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayRows.count else { return nil }
        if case .header(let title) = displayRows[row] {
            return groupHeaderView(tableView, title: title)
        }
        guard let identifier = tableColumn?.identifier, let node = node(atRow: row) else { return nil }

        let reuseID = NSUserInterfaceItemIdentifier(identifier.rawValue)
        if FileColumn(rawValue: identifier.rawValue) == .tags {
            let chips = (tableView.makeView(withIdentifier: reuseID, owner: self) as? TagChipsCellView) ?? {
                let view = TagChipsCellView()
                view.identifier = reuseID
                return view
            }()
            chips.tags = node.tags
            return chips
        }
        let cell: NSTableCellView
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: reuseID, owner: self) as? NSTableCellView,
           let reusedField = reused.textField {
            cell = reused
            textField = reusedField
        } else {
            cell = NSTableCellView()
            cell.identifier = reuseID
            textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
        }

        switch FileColumn(rawValue: identifier.rawValue) {
        case .name:
            let imageView: NSImageView
            if let existing = cell.imageView {
                imageView = existing
            } else {
                imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cell.addSubview(imageView)
                cell.imageView = imageView
                // Compare Panes' status, after the name; empty otherwise.
                let badge = NSTextField(labelWithString: "")
                badge.identifier = Self.comparisonBadgeID
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .semibold)
                badge.setContentHuggingPriority(.required, for: .horizontal)
                badge.setContentCompressionResistancePriority(.required, for: .horizontal)
                textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                cell.addSubview(badge)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            if let badge = comparisonBadge(in: cell) {
                let status = comparisonStatuses?[node.name]
                badge.stringValue = status.map(ComparisonStatusStyle.label) ?? ""
                badge.textColor = status.map(ComparisonStatusStyle.color) ?? .secondaryLabelColor
                badge.toolTip = status.map(ComparisonStatusStyle.explanation)
            }
            // A package (e.g. a .app bundle) is a directory on disk but gets
            // its real icon like any other file, not the generic folder
            // artwork — it's treated as a launchable item, not a folder.
            imageView.image = (node.isDirectory && !node.isPackage) ? ThemedIcons.image(.folder, theme: theme) : NSWorkspace.shared.icon(forFile: node.url.path)
            textField.stringValue = node.name
        case .dateModified:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.modificationDate.map { FileDateFormat.string(from: $0) } ?? ""
        case .dateCreated:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.creationDate.map { FileDateFormat.string(from: $0) } ?? ""
        case .dateAdded:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.dateAdded.map { FileDateFormat.string(from: $0) } ?? ""
        case .dateLastOpened:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.lastOpenedDate.map { FileDateFormat.string(from: $0) } ?? ""
        case .size:
            pinIfNeeded(textField, in: cell)
            if node.isDirectory {
                if let size = folderSizes[node.url] {
                    textField.stringValue = Self.byteFormatter.string(fromByteCount: size)
                } else {
                    textField.stringValue = calculatingFolderSizes.contains(node.url) ? "Calculating\u{2026}" : "--"
                }
            } else {
                textField.stringValue = node.size.map { Self.byteFormatter.string(fromByteCount: $0) } ?? ""
            }
        case .kind:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.isDirectory ? "Folder" : (node.kind ?? "")
        case .tags:
            break // drawn as chips above
        case .fileExtension:
            pinIfNeeded(textField, in: cell)
            textField.stringValue = node.fileExtension
        case .location:
            pinIfNeeded(textField, in: cell)
            let folder = node.url.deletingLastPathComponent()
            textField.stringValue = (folder.path as NSString).abbreviatingWithTildeInPath
            textField.toolTip = folder.path
            textField.lineBreakMode = .byTruncatingHead
        case nil:
            break
        }
        // The name reads first; the metadata columns stay quieter.
        textField.textColor = FileColumn(rawValue: identifier.rawValue) == .name ? theme.textNSColor : theme.secondaryTextNSColor
        return cell
    }

    private func pinIfNeeded(_ textField: NSTextField, in cell: NSTableCellView) {
        guard textField.constraints.isEmpty, cell.subviews.contains(textField) else { return }
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }

    /// Keeps the column header's built-in sort-indicator arrow in sync with
    /// a sort chosen from the shortcut toolbar's Sort menu — clicking a
    /// header directly already updates `tableView.sortDescriptors` (and
    /// the arrow) via AppKit itself, but that path never runs for a sort
    /// initiated elsewhere, so the arrow would otherwise keep pointing at
    /// whatever column was last clicked.
    func updateSortIndicator(field: FileColumn, direction: SortDirection) {
        let descriptor = NSSortDescriptor(key: field.rawValue, ascending: direction == .ascending)
        let current = tableView.sortDescriptors.first
        guard current?.key != descriptor.key || current?.ascending != descriptor.ascending else { return }
        isSyncingSortDescriptor = true
        tableView.sortDescriptors = [descriptor]
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncingSortDescriptor else {
            isSyncingSortDescriptor = false
            return
        }
        guard let key = tableView.sortDescriptors.first?.key, let column = FileColumn(rawValue: key) else { return }
        onSortChange?(column)
    }

    @objc private func handleDoubleClick() {
        guard let node = node(atRow: tableView.clickedRow) else { return }
        actions.openOnDoubleClick(node)
    }

    // MARK: Column header menu

    /// The table's own delegate is only for the column header's menu; the
    /// item context menu's delegate is `actions`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildColumnMenu(menu)
    }
}
