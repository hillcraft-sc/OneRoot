import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The destinations sidebar: Home and the user folders, Pinned, Locations
/// (drives and shares), Trash and Workspaces — `DestinationsViewModel`'s
/// sections plus the app's Workspaces, in a navigation-sidebar list.
@MainActor
final class Sidebar {
    enum Entry {
        case destination(Destination)
        case workspace(Workspace)
    }

    let widget: ScrolledWindow
    var onSelect: ((Entry, _ inNewTab: Bool) -> Void)?
    var onContextMenu: ((Entry, Widget, Double, Double) -> Void)?
    /// The + beside the Workspaces heading.
    var onNewWorkspace: (() -> Void)?
    /// The Network row (servers found on the local network).
    var onBrowseNetwork: (() -> Void)?
    private var networkRowIndex: Int?
    private var popover: PopoverMenu?
    /// Files were dropped on a folder destination.
    var onDropFiles: (([URL], _ folder: URL, _ move: Bool) -> Void)?
    /// Files dropped on the Trash row.
    var onTrashFiles: (([URL]) -> Void)?

    private let list = ListBox()
    private let destinations: DestinationsViewModel
    private let workspaces: WorkspaceStore
    private var entries: [Entry?] = []
    private var watches: [ObservationWatch] = []
    private var isRebuilding = false
    private var highlightedURL: URL?

    init(destinations: DestinationsViewModel, workspaces: WorkspaceStore? = nil) {
        self.destinations = destinations
        let workspaces = workspaces ?? .shared
        self.workspaces = workspaces
        list.addCSSClass("navigation-sidebar")
        list.setAccessibleLabel("Destinations")
        list.selectionMode = GTK_SELECTION_SINGLE
        widget = ScrolledWindow(child: list)
        widget.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        widget.vexpand = true

        list.onRowActivated { [weak self] row in
            guard let self, !self.isRebuilding, row.index < self.entries.count else { return }
            if row.index == self.networkRowIndex {
                self.onBrowseNetwork?()
                return
            }
            guard let entry = self.entries[row.index] else { return }
            self.onSelect?(entry, false)
        }

        watches.append(ObservationWatch.watch({ (destinations.sections, workspaces.workspaces) }) { [weak self] _ in
            self?.rebuild()
        })
    }

    /// Shows which destination the active tab is in.
    func highlight(_ url: URL?) {
        highlightedURL = url
        isRebuilding = true
        defer { isRebuilding = false }
        guard let url else {
            list.unselectAll()
            return
        }
        let index = entries.firstIndex { entry in
            if case .destination(let destination)? = entry { return destination.url.standardizedFileURL == url.standardizedFileURL }
            return false
        }
        if let index { list.selectRow(at: index) } else { list.unselectAll() }
    }

    private func rebuild() {
        isRebuilding = true
        defer { isRebuilding = false }
        list.removeAll()
        entries = []
        networkRowIndex = nil
        for section in destinations.sections {
            if !section.title.isEmpty { appendHeader(section.title) }
            for destination in section.destinations {
                // Home is "Home" here, as on every Linux desktop.
                let name = destination.kind == .home ? "Home" : destination.name
                appendRow(.destination(destination), name: name, icon: FileIcons.symbolicName(for: destination),
                          iconClass: ThemeCSS.iconClass(for: destination.kind), ejectable: destination.isEjectable ? destination : nil)
            }
            if section.title == "Locations" { appendNetworkRow() }
        }
        appendHeader("Workspaces")
        for workspace in workspaces.workspaces {
            appendRow(.workspace(workspace), name: workspace.name, icon: WorkspaceIcons.iconName(for: workspace.symbolName), ejectable: nil)
        }
        if workspaces.workspaces.isEmpty {
            let hint = Label("Drop folders here to start one")
            hint.xalign = 0
            hint.addCSSClass(.dimLabel)
            hint.addCSSClass("caption")
            hint.marginStart = 8
            let row = ListBoxRow()
            row.child = hint
            row.selectable = false
            row.activatable = false
            list.append(row)
            entries.append(nil)
            // Folders dropped here start a Workspace.
            attachWorkspaceTarget(to: row) { [weak self] folders in
                guard let self, let first = folders.first else { return }
                let workspace = self.workspaces.create(with: first)
                if folders.count > 1 { self.workspaces.addFolders(Array(folders.dropFirst()), to: workspace.id) }
            }
        }
        let url = highlightedURL
        isRebuilding = false
        highlight(url)
    }

    /// "Network": not a folder, so it has no entry; activating it opens the browser.
    private func appendNetworkRow() {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        box.append(Image(iconName: "network-workgroup-symbolic"))
        let label = Label("Network")
        label.xalign = 0
        label.hexpand = true
        box.append(label)
        let row = ListBoxRow()
        row.child = box
        row.setAccessibleLabel("Network, browse servers on your network")
        list.append(row)
        networkRowIndex = entries.count
        entries.append(nil)
    }

    /// A right-click menu for a row, over `GMenuRef` items whose actions the
    /// window provides.
    func showMenu(_ model: GMenuRef, in row: Widget, x: Double, y: Double) {
        popover?.unparent()
        guard let raw = gtk_popover_menu_new_from_model(model.menuModelPointer) else { return }
        let object = UnsafeMutableRawPointer(raw)
        g_object_ref_sink(object)
        let menu = PopoverMenu(borrowing: object)
        g_object_unref(object)
        menu.hasArrow = false
        menu.halign = GTK_ALIGN_START
        menu.setParent(row)
        menu.setPointingTo(x: Int(x), y: Int(y))
        _ = menu.popup()
        popover = menu
    }

    private func appendHeader(_ title: String) {
        let label = Label(title)
        label.xalign = 0
        label.hexpand = true
        label.addCSSClass("heading")
        label.addCSSClass(.dimLabel)
        label.marginStart = 6
        let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        content.marginTop = 12
        content.append(label)
        if title == "Workspaces" {
            let add = Button(iconName: "list-add-symbolic")
            add.addCSSClass(.flat)
            add.addCSSClass("circular")
            add.tooltipText = "New Workspace\u{2026}"
            add.setAccessibleLabel("New Workspace")
            add.onClicked { [weak self] in self?.onNewWorkspace?() }
            content.append(add)
        }
        let row = ListBoxRow()
        row.child = content
        row.selectable = false
        row.activatable = false
        list.append(row)
        entries.append(nil)
    }

    private func appendRow(_ entry: Entry, name: String, icon: String, iconClass: String? = nil, ejectable: Destination?) {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        let image = Image(iconName: icon)
        if let iconClass { image.addCSSClass(iconClass) }
        box.append(image)
        let label = Label(name)
        label.xalign = 0
        label.hexpand = true
        label.ellipsize = PANGO_ELLIPSIZE_END
        box.append(label)
        if let ejectable {
            let eject = Button(iconName: "media-eject-symbolic")
            eject.hasFrame = false
            eject.tooltipText = "Eject \(ejectable.name)"
            eject.setAccessibleLabel("Eject \(ejectable.name)")
            eject.addCSSClass(.flat)
            eject.onClicked { [weak self] in self?.destinations.eject(ejectable) }
            box.append(eject)
        }
        let row = ListBoxRow()
        row.child = box
        row.tooltipText = Self.tooltip(for: entry)
        list.append(row)
        entries.append(entry)

        let rightClick = GestureClick()
        rightClick.button = 3
        rightClick.onPressed { [weak self, weak row] _, x, y in
            guard let self, let row else { return }
            self.onContextMenu?(entry, row, x, y)
        }
        row.addController(rightClick)

        switch entry {
        case .destination(let destination) where !destination.kind.isVirtual && destination.kind != .trash:
            let rowPointer = row.pointer
            DragAndDrop.attachFileTarget(to: row, destination: { destination.url }, highlight: { on in
                Self.setDropHighlight(rowPointer, on)
            }, drop: { [weak self] urls, folder, move in
                self?.onDropFiles?(urls, folder, move)
            })
        case .destination(let destination) where destination.kind == .trash:
            let rowPointer = row.pointer
            DragAndDrop.attachTarget(to: row, actions: GDK_ACTION_MOVE, highlight: { on in
                Self.setDropHighlight(rowPointer, on)
            }, choose: { urls, _, _, _ in
                urls.contains { Platform.isTrashFolder($0.deletingLastPathComponent()) } ? DragAndDrop.none : GDK_ACTION_MOVE
            }, drop: { [weak self] urls, _ in
                self?.onTrashFiles?(urls)
                return true
            })
        case .workspace(let workspace):
            attachWorkspaceTarget(to: row) { [weak self] folders in
                self?.workspaces.addFolders(folders, to: workspace.id)
            }
        default:
            break
        }

        // Middle-click: in a new tab, as in a browser.
        let middleClick = GestureClick()
        middleClick.button = 2
        middleClick.onPressed { [weak self] _, _, _ in self?.onSelect?(entry, true) }
        row.addController(middleClick)
    }

    /// Folders dropped on `row` are added to a Workspace by `add`; files that
    /// aren't folders are ignored (a Workspace is a set of folders).
    private func attachWorkspaceTarget(to row: ListBoxRow, add: @escaping ([URL]) -> Void) {
        let rowPointer = row.pointer
        DragAndDrop.attachTarget(to: row, actions: GDK_ACTION_COPY, highlight: { on in
            Self.setDropHighlight(rowPointer, on)
        }, choose: { urls, _, _, _ in
            urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ? GDK_ACTION_COPY : DragAndDrop.none
        }, drop: { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            guard !folders.isEmpty else { return false }
            add(folders)
            return true
        })
    }

    private static func setDropHighlight(_ pointer: UnsafeMutableRawPointer, _ on: Bool) {
        let widget = pointer.assumingMemoryBound(to: GtkWidget.self)
        if on { gtk_widget_add_css_class(widget, "oneroot-drop-target") } else { gtk_widget_remove_css_class(widget, "oneroot-drop-target") }
    }

    private static func tooltip(for entry: Entry) -> String {
        switch entry {
        case .destination(let destination):
            return destination.kind.isVirtual ? destination.name : destination.url.path
        case .workspace(let workspace):
            return workspace.folders.map(\.path).joined(separator: "\n")
        }
    }
}
