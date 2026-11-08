import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Context Bar: the selection-aware row under the tabs (as on the Mac).
/// With nothing selected it offers New; with a selection, that selection's
/// actions (Cut, Copy, Rename, …). On the right: a Paste chip while the
/// clipboard holds files, Sort, List/Grid, Dual Pane and More.
/// Every button is a window action, so it greys out with the action and the
/// keyboard and menus do exactly the same thing.
@MainActor
final class ContextBar {
    let widget = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
    private let leftSlot = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
    private let pasteButton = Button(label: "Paste")
    private let listButton = ToggleButton()
    private let gridButton = ToggleButton()
    private var watches: [ObservationWatch] = []
    private var pasteTask: Task<Void, Never>?
    private weak var pane: FileListViewModel?
    private var shown: Shown?

    /// What the left side currently shows, to rebuild only on a change.
    private enum Shown: Equatable {
        case new
        case selection(count: Int, inTrash: Bool, hasFolder: Bool, canExtract: Bool, quick: [String])
    }

    /// Reads the folder the bar acts on is in the Trash.
    var isInTrash: () -> Bool = { false }
    /// The Quick Actions for the selection (none in the Trash).
    var quickOptions: () -> [QuickActionOption] = { [] }
    /// Switches the view of the focused pane.
    var onViewMode: ((FileViewMode) -> Void)?

    /// Shown while Dual Pane is on.
    let compareButton = Button()
    /// Grid view only: the icon size.
    private let iconSizeScale = Scale(min: Double(GridIconSize.range.lowerBound), max: Double(GridIconSize.range.upperBound), step: 8)

    init(dualPaneButton: ToggleButton) {
        widget.addCSSClass("oneroot-context-bar")
        widget.marginStart = 10
        widget.marginEnd = 10
        widget.marginTop = 4
        widget.marginBottom = 4

        // The left side may be wider than a narrow window: it scrolls
        // sideways instead of setting the window's minimum width.
        let leftScroller = ScrolledWindow(child: leftSlot)
        leftScroller.setPolicy(horizontal: GTK_POLICY_EXTERNAL, vertical: GTK_POLICY_NEVER)
        leftScroller.hexpand = true
        widget.append(leftScroller)

        pasteButton.addCSSClass(.flat)
        pasteButton.iconName = "edit-paste-symbolic"
        pasteButton.setAccessibleLabel("Paste")
        pasteButton.tooltipText = "Paste (Ctrl+V)"
        Self.bind(pasteButton, to: "win.paste")
        pasteButton.visible = false
        widget.append(pasteButton)

        widget.append(Self.menuButton(title: "Sort", icon: "view-sort-ascending-symbolic",
                                      tooltip: "Sort by", model: Self.sortMenu()))

        let views = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        views.addCSSClass(.linked)
        listButton.child = Image(iconName: "view-list-symbolic")
        listButton.tooltipText = "List (Ctrl+2)"
        listButton.setAccessibleLabel("View as list")
        gridButton.child = Image(iconName: "view-grid-symbolic")
        gridButton.tooltipText = "Grid (Ctrl+1)"
        gridButton.setAccessibleLabel("View as grid")
        gtk_toggle_button_set_group(gridButton.pointer.assumingMemoryBound(to: GtkToggleButton.self), listButton.pointer.assumingMemoryBound(to: GtkToggleButton.self))
        listButton.onToggled { [weak self] in
            if self?.listButton.active == true { self?.onViewMode?(.list) }
        }
        gridButton.onToggled { [weak self] in
            if self?.gridButton.active == true { self?.onViewMode?(.icons) }
        }
        views.append(listButton)
        views.append(gridButton)
        iconSizeScale.drawValue = false
        iconSizeScale.setSizeRequest(width: 110, height: -1)
        iconSizeScale.value = Double(GridIconSize.shared.size)
        iconSizeScale.tooltipText = "Icon size"
        iconSizeScale.setAccessibleLabel("Icon size")
        iconSizeScale.visible = false
        iconSizeScale.onValueChanged { GridIconSize.shared.set(Int(self.iconSizeScale.value)) }
        widget.append(iconSizeScale)
        widget.append(views)

        widget.append(dualPaneButton)
        compareButton.addCSSClass(.flat)
        compareButton.iconName = "edit-find-replace-symbolic"
        compareButton.tooltipText = "Compare Panes (Ctrl+Alt+\\)"
        compareButton.setAccessibleLabel("Compare Panes")
        Self.bind(compareButton, to: "win.compare-panes")
        compareButton.visible = false
        widget.append(compareButton)
        widget.append(Self.menuButton(title: "More", icon: "view-more-symbolic",
                                      tooltip: "More actions", model: Self.moreMenu()))
    }

    // MARK: Binding

    /// Follows `pane` (the focused one): its selection, view mode, and the
    /// clipboard.
    func bind(to pane: FileListViewModel) {
        self.pane = pane
        watches = []
        watches.append(ObservationWatch.watch({ (pane.selectedNodes.map(\.url), pane.currentLocationURL) }) { [weak self] _ in
            self?.rebuildLeft()
        })
        watches.append(ObservationWatch.watch({ pane.viewMode }) { [weak self] mode in
            guard let self else { return }
            let button = mode == .icons ? self.gridButton : self.listButton
            self.iconSizeScale.visible = mode == .icons
            if !button.active { button.active = true }
        })
        refreshPaste()
        startPastePolling()
    }

    /// The clipboard isn't observable, so it is checked once a second
    /// (cheap) — the chip then goes away when something else replaces it.
    private func startPastePolling() {
        pasteTask?.cancel()
        pasteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.refreshPaste()
            }
        }
    }

    private func refreshPaste() {
        pasteButton.visible = pane?.canPaste ?? false
    }

    // MARK: Left side

    private func rebuildLeft() {
        guard let pane else { return }
        let nodes = pane.selectedNodes
        let state: Shown = nodes.isEmpty
            ? .new
            : .selection(count: nodes.count, inTrash: isInTrash(), hasFolder: nodes.contains(where: \.isDirectory), canExtract: pane.canExtract(nodes),
                         quick: quickOptions().map { "\($0.action.rawValue):\($0.isAvailable)" })
        refreshPaste()
        guard state != shown else { return }
        shown = state
        while let child = leftSlot.firstChild { leftSlot.remove(child) }
        switch state {
        case .new:
            let menu = GMenuRef()
            menu.append("New Folder", action: "win.new-folder")
            menu.append("New File", action: "win.new-file")
            menu.append("New Folder and Open", action: "win.new-folder-open")
            leftSlot.append(Self.menuButton(title: "New", icon: "list-add-symbolic", tooltip: "New folder or file", model: menu))
        case .selection(let count, let trash, let hasFolder, let canExtract, _):
            // "N selected" with a ✕ that clears it, as on the Mac.
            let total = Label(count == 1 ? "1 selected" : "\(count) selected")
            total.addCSSClass("heading")
            total.marginStart = 6
            leftSlot.append(total)
            let deselect = Button(iconName: "window-close-symbolic")
            deselect.addCSSClass(.flat)
            deselect.tooltipText = "Deselect All (Shift+Ctrl+A)"
            deselect.setAccessibleLabel("Deselect All")
            Self.bind(deselect, to: "win.deselect-all")
            leftSlot.append(deselect)
            var buttons: [(String, String, String, String)] = []  // icon, label, action, tooltip
            if trash {
                buttons = [("edit-undo-symbolic", "Restore", "win.restore", "Restore to where it came from"),
                           ("edit-delete-symbolic", "Delete Permanently", "win.delete-permanently", "Delete permanently (Shift+Delete)")]
            } else {
                buttons.append(("document-open-symbolic", "Open", "win.open", "Open (Enter)"))
                if hasFolder { buttons.append(("tab-new-symbolic", "Open in New Tab", "win.open-new-tab", "Open in a new tab (Ctrl+Enter)")) }
                buttons += [("edit-cut-symbolic", "Cut", "win.cut", "Cut (Ctrl+X)"),
                            ("edit-copy-symbolic", "Copy", "win.copy", "Copy (Ctrl+C)"),
                            ("document-edit-symbolic", "Rename", "win.rename", "Rename (F2)"),
                            ("package-x-generic-symbolic", "Compress", "win.compress", "Compress")]
                if canExtract { buttons.append(("folder-download-symbolic", "Extract", "win.extract", "Extract here")) }
                buttons.append(("user-trash-symbolic", "Move to Trash", "win.trash", "Move to Trash (Delete)"))
            }
            for (icon, label, action, tooltip) in buttons {
                let button = Button(iconName: icon)
                button.addCSSClass(.flat)
                button.tooltipText = tooltip
                button.setAccessibleLabel(label)
                Self.bind(button, to: action)
                leftSlot.append(button)
            }
            if !trash, let quick = AppWindow.quickActionsMenu(for: quickOptions()) {
                leftSlot.append(Self.menuButton(title: "Quick Actions", icon: "applications-engineering-symbolic",
                                                tooltip: "Resize, convert, combine into PDF\u{2026}", model: quick))
            }
        }
    }

    // MARK: Menus

    private static func bind(_ button: Widget, to action: String) {
        gtk_actionable_set_action_name(OpaquePointer(button.pointer), action)
    }

    private static func menuButton(title: String, icon: String, tooltip: String, model: GMenuRef) -> MenuButton {
        let button = MenuButton()
        let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        content.append(Image(iconName: icon))
        content.append(Label(title))
        gtk_menu_button_set_child(button.opaquePointer, content.widgetPointer)
        button.addCSSClass(.flat)
        button.tooltipText = tooltip
        button.setAccessibleLabel(title)
        button.setMenuModel(model)
        return button
    }

    /// Sort fields offered, in order.
    static let sortFields: [FileColumn] = [.name, .dateModified, .size, .kind, .dateCreated]

    private static func sortMenu() -> GMenuRef {
        let menu = GMenuRef()
        for field in sortFields {
            let item = GMenuItemRef(label: field.title, action: "win.sort-by")
            item.setTargetValue(Variant.string(field.rawValue))
            menu.appendItem(item)
        }
        let grouping = GMenuRef()
        let none = GMenuItemRef(label: "None", action: "win.group-by")
        none.setTargetValue(Variant.string("none"))
        grouping.appendItem(none)
        for field in groupFields {
            let item = GMenuItemRef(label: field.title, action: "win.group-by")
            item.setTargetValue(Variant.string(field.rawValue))
            grouping.appendItem(item)
        }
        menu.appendSection("Group by", section: grouping)
        return menu
    }

    /// Group-by fields offered, in order.
    static let groupFields: [FileColumn] = [.name, .kind, .dateModified, .size, .tags]

    private static func moreMenu() -> GMenuRef {
        let menu = GMenuRef()
        func section(_ items: [(String, String)]) {
            let section = GMenuRef()
            for (label, action) in items { section.append(label, action: action) }
            menu.appendSection(nil, section: section)
        }
        section([("Select All", "win.select-all"), ("Duplicate", "win.duplicate"), ("Copy Path", "win.copy-path")])
        section([("Open in Terminal", "win.open-terminal"), ("Pin to Sidebar", "win.pin")])
        section([("Show Hidden Files", "win.show-hidden"), ("Columns\u{2026}", "win.columns"), ("Show All Files in Subfolders", "win.show-all-files"), ("Calculate Folder Sizes", "win.calculate-size")])
        section([("Connect to Server\u{2026}", "win.connect-to-server"), ("Browse Network\u{2026}", "win.browse-network")])
        section([("Find Duplicates\u{2026}", "win.find-duplicates"), ("Visualize Storage", "win.visualize"),
                 ("Advanced Search\u{2026}", "win.advanced-search")])
        return menu
    }
}
