import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// What the chip row and its editors read and change: a folder's filter or
/// Advanced Search's criteria.
struct FilterSource {
    let criteria: () -> SearchCriteria
    let update: (SearchCriteria) -> Void
    var tagsInFolder: () -> [[String]] = { [] }
    /// Why the name can't be used (an unfinished regex), shown on its chip.
    var nameError: () -> String? = { nil }
    let context: SearchChipContext
}

/// The chips for a `SearchCriteria` — the shared `SearchChipBuilder`'s —
/// with ✕ to remove, click to edit, and Add Filter. One popover, anchored to
/// `host` (which survives the chip rebuilds a change causes), shows the Add
/// Filter list and then the chosen editor.
@MainActor
final class ChipRow {
    let source: FilterSource
    /// The chips, scrollable sideways.
    let widget: ScrolledWindow
    private let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
    private let host: Widget
    private let popover = Popover()
    private var currentEditor: FilterEditor?

    init(source: FilterSource, host: Widget) {
        self.source = source
        self.host = host
        widget = ScrolledWindow(child: row)
        widget.setPolicy(horizontal: GTK_POLICY_AUTOMATIC, vertical: GTK_POLICY_NEVER)
        widget.hexpand = true
        widget.setAccessibleLabel("Filters")
        popover.hasArrow = true
        popover.autohide = true
        popover.position = GTK_POS_BOTTOM
        popover.addCSSClass("oneroot-filter-editor")
    }

    /// The chips to show. A plain name filter is the field's own text, so it
    /// gets no chip; Match Case, a regex or starts/ends-with does.
    func chips() -> [SearchChip] {
        let filter = source.criteria()
        return SearchChipBuilder.chips(for: filter, context: source.context).filter { chip in
            switch chip.field {
            case .name: return !(filter.patternMode == .contains && !filter.caseSensitive)
            case .contents: return false
            default: return true
            }
        }
    }

    /// Redraws the chips; the number shown.
    @discardableResult
    func rebuild() -> Int {
        while let child = row.firstChild { row.remove(child) }
        let shown = chips()
        for chip in shown { row.append(makeChip(chip)) }
        return shown.count
    }

    private func makeChip(_ chip: SearchChip) -> Widget {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        box.addCSSClass("oneroot-chip")
        let error = chip.field == .name ? source.nameError() : nil
        if error != nil { box.addCSSClass("oneroot-chip-error") }

        let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        content.append(Image(iconName: Self.icon(for: chip.field)))
        let label = Label(chip.title)
        label.ellipsize = PANGO_ELLIPSIZE_END
        label.maxWidthChars = 32
        content.append(label)
        let main = Button()
        main.child = content
        main.addCSSClass(.flat)
        main.tooltipText = error ?? "Change this filter"
        main.setAccessibleLabel(chip.title)
        let field = chip.field
        main.onClicked { [weak self, weak box] in
            guard let self, let box else { return }
            self.showEditor(for: field, anchor: box)
        }

        let remove = Button(iconName: "window-close-symbolic")
        remove.addCSSClass(.flat)
        remove.addCSSClass(.circular)
        remove.tooltipText = "Remove this filter"
        remove.setAccessibleLabel("Remove \(chip.title)")
        remove.onClicked { [weak self] in
            guard let self else { return }
            self.source.update(SearchChipBuilder.removing(field, from: self.source.criteria()))
        }
        box.append(main)
        box.append(remove)
        return box
    }

    static func icon(for field: SearchChip.Field) -> String {
        switch field {
        case .name: return "format-text-bold-symbolic"
        case .contents: return "edit-find-symbolic"
        case .itemType: return "folder-symbolic"
        case .extensions: return "text-x-generic-symbolic"
        case .size: return "drive-harddisk-symbolic"
        case .modifiedWithin, .modifiedDates: return "x-office-calendar-symbolic"
        case .kinds: return "view-grid-symbolic"
        case .tag: return "tag-symbolic"
        case .includeHidden: return "view-reveal-symbolic"
        case .includeCloudStorage: return "weather-overcast-symbolic"
        }
    }

    // MARK: Popover

    private static let addable: [SearchChip.Field] = [.kinds, .modifiedWithin, .size, .extensions, .tag(""), .itemType, .name]

    private static func menuTitle(_ field: SearchChip.Field) -> String {
        switch field {
        case .kinds: return "Kind\u{2026}"
        case .modifiedWithin, .modifiedDates: return "Date Modified\u{2026}"
        case .size: return "Size\u{2026}"
        case .extensions: return "Extension\u{2026}"
        case .tag: return "Tag\u{2026}"
        case .itemType: return "Files or Folders\u{2026}"
        default: return "Name Options\u{2026}"
        }
    }

    private func present(_ content: Widget, anchor: Widget) {
        // After the click that asked for it finishes: the content being
        // replaced may be the very button that was clicked.
        MainContext.task { [weak self] in self?.presentNow(content, anchor: anchor) }
    }

    private func presentNow(_ content: Widget, anchor: Widget) {
        popover.child = content
        var x = 0.0, y = 0.0
        _ = gtk_widget_translate_coordinates(anchor.widgetPointer, host.widgetPointer, 0, 0, &x, &y)
        let width = max(1, Int(gtk_widget_get_width(anchor.widgetPointer)))
        let height = max(1, Int(gtk_widget_get_height(anchor.widgetPointer)))
        popover.present(from: host, x: Int(x), y: Int(y), width: width, height: height)
    }

    func showMenu(anchor: Widget) {
        let list = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        for field in Self.addable where !(field == .name && source.context == .advancedSearch) {
            let button = Button(label: Self.menuTitle(field))
            button.addCSSClass(.flat)
            (button.child as? Label)?.xalign = 0
            button.onClicked { [weak self] in self?.showEditor(for: field, anchor: anchor) }
            list.append(button)
        }
        present(list, anchor: anchor)
    }

    private func showEditor(for field: SearchChip.Field, anchor: Widget) {
        // Kept: the editor's controls call back into it.
        let editor = FilterEditor(source: source, field: field)
        currentEditor = editor
        present(editor.widget, anchor: anchor)
    }
}

/// The search field and filter chips above one pane's file list — the GTK
/// counterpart of the Mac's search field and `FolderFilterBar`. It edits the
/// list's `filter` (the shared `SearchCriteria`), so the view model does the
/// matching.
///
/// Hidden until opened (Ctrl+F or /) or while anything filters the list — the
/// filter stays on from folder to folder until cleared, as on the Mac.
@MainActor
final class FilterBar {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
    /// Escape in the field with nothing left to clear: back to the list.
    var onReturnToList: (() -> Void)?
    /// Search Subfolders: this folder's filter as an Advanced Search.
    var onSearchSubfolders: ((SearchCriteria) -> Void)?

    private let viewModel: FileListViewModel
    private let entry = SearchEntry()
    private let addButton = Button()
    private let chipLine = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
    private let countLabel = Label("")
    private let chipRow: ChipRow
    private var isOpen = false
    private var watches: [ObservationWatch] = []

    init(viewModel: FileListViewModel) {
        self.viewModel = viewModel
        chipRow = ChipRow(source: FilterSource(
            criteria: { [weak viewModel] in viewModel?.filter ?? SearchCriteria(root: URL(fileURLWithPath: "/")) },
            update: { [weak viewModel] in viewModel?.filter = $0 },
            tagsInFolder: { [weak viewModel] in viewModel?.tagsInFolder ?? [] },
            nameError: { [weak viewModel] in viewModel?.filterError },
            context: .folder
        ), host: widget)
        widget.addCSSClass("oneroot-filter-bar")
        widget.visible = false

        entry.placeholderText = "Filter this folder by name"
        entry.hexpand = true
        entry.setAccessibleLabel("Filter by name")
        entry.onSearchChanged { [weak self] in
            guard let self, self.viewModel.filter.pattern != self.entry.text else { return }
            self.viewModel.searchText = self.entry.text
        }
        entry.onStopSearch { [weak self] in self?.escape() }

        let addContent = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        addContent.append(Image(iconName: "list-add-symbolic"))
        addContent.append(Label("Add Filter"))
        addButton.child = addContent
        addButton.onClicked { [weak self] in
            guard let self else { return }
            self.chipRow.showMenu(anchor: self.addButton)
        }

        let fieldRow = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        fieldRow.append(entry)
        fieldRow.append(addButton)

        countLabel.addCSSClass(.dimLabel)
        countLabel.addCSSClass("caption")
        let subfolders = Button(label: "Search Subfolders")
        subfolders.tooltipText = "Search this folder and everything inside it with these filters, in Advanced Search"
        subfolders.onClicked { [weak self] in
            guard let self, let criteria = self.viewModel.filterAsSubfolderSearch() else { return }
            self.onSearchSubfolders?(criteria)
        }
        let clear = Button(label: "Clear")
        clear.tooltipText = "Remove every filter"
        clear.onClicked { [weak self] in self?.viewModel.clearFilter() }
        chipLine.append(chipRow.widget)
        chipLine.append(countLabel)
        chipLine.append(subfolders)
        chipLine.append(clear)

        widget.append(fieldRow)
        widget.append(chipLine)

        watches.append(ObservationWatch.watch({ viewModel.filter }) { [weak self] _ in self?.filterChanged() })
        watches.append(ObservationWatch.watch({ viewModel.items.count }) { [weak self] count in
            self?.countLabel.text = count == 1 ? "1 match" : "\(count) matches"
        })
        watches.append(ObservationWatch.watch({ viewModel.filterError }) { [weak self] message in
            guard let self else { return }
            if let message {
                self.entry.addCSSClass(.error)
                self.entry.tooltipText = message
            } else {
                self.entry.removeCSSClass(.error)
                self.entry.tooltipText = nil
            }
        })
        watches.append(ObservationWatch.watch({ viewModel.searchFieldFocusTrigger }, emitsInitialValue: false) { [weak self] _ in
            self?.focusEntry()
        })
    }

    /// Shows the bar and puts the cursor in the field (Ctrl+F, /).
    func focusEntry() {
        isOpen = true
        updateVisibility()
        _ = entry.grabFocus()
        gtk_editable_select_region(OpaquePointer(entry.pointer), 0, -1)
    }

    private func escape() {
        if !entry.text.isEmpty {
            viewModel.searchText = ""
            return
        }
        isOpen = false
        updateVisibility()
        onReturnToList?()
    }

    private func updateVisibility() {
        widget.visible = isOpen || viewModel.filter.hasFilters
        chipLine.visible = viewModel.filter.hasFilters
    }

    private func filterChanged() {
        let pattern = viewModel.filter.pattern
        if entry.text != pattern { entry.text = pattern }
        chipRow.rebuild()
        updateVisibility()
    }
}
