import Adwaita
import CAdwaita
import Foundation
import Observation
@testable import OneRoot

/// Find Duplicates: groups of identical files in the current folder (both
/// folders with Dual Pane on), with the copies you mark moved to the Trash —
/// one of each group always stays. The GTK counterpart of the Mac's
/// DuplicatesView over the shared `DuplicatesViewModel`; its own window, so a
/// long scan doesn't hold up browsing.
@MainActor
final class DuplicatesWindow {
    let window: ApplicationWindow
    let viewModel = DuplicatesViewModel()
    /// Shows a file in its folder, in a new tab.
    var onShowInFolder: ((URL) -> Void)?
    /// The window was closed.
    var onClose: (() -> Void)?

    private let titleLabel = Label("Find Duplicates")
    private let summaryLabel = Label("")
    private let spinner = Image(iconName: "content-loading-symbolic")
    private let scanButton = Button(label: "Scan Again")
    private let list = ListBox()
    private let stack = Stack()
    private let emptyPage = StatusPage()
    private let keepOldest = Button(label: "Mark All but Oldest")
    private let keepNewest = Button(label: "Mark All but Newest")
    private let clearButton = Button(label: "Clear")
    private let trashButton = Button(label: "Move to Trash")
    private var watches: [ObservationWatch] = []
    private var isRebuilding = false

    init(application: Application) {
        window = ApplicationWindow(application: application)
        window.title = "Find Duplicates"
        window.defaultWidth = 760
        window.defaultHeight = 560
        buildLayout()
        installMenuActions()
        wire()
        refresh()
    }

    func present() {
        window.present()
    }

    /// Scans `roots` (a hand-off from the file window).
    func start(_ roots: [URL]) {
        guard !roots.isEmpty else { return }
        viewModel.start(roots)
    }

    // MARK: Layout

    private func buildLayout() {
        titleLabel.xalign = 0
        titleLabel.hexpand = true
        titleLabel.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        titleLabel.addCSSClass("heading")
        summaryLabel.xalign = 0
        summaryLabel.wrap = true
        summaryLabel.addCSSClass(.dimLabel)
        summaryLabel.addCSSClass("caption")
        let text = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        text.hexpand = true
        text.append(titleLabel)
        text.append(summaryLabel)

        spinner.pixelSize = 16
        spinner.visible = false
        scanButton.setAccessibleLabel("Scan Again")
        let header = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        header.marginStart = 14
        header.marginEnd = 14
        header.marginTop = 10
        header.marginBottom = 10
        header.append(text)
        header.append(spinner)
        header.append(scanButton)

        list.selectionMode = GTK_SELECTION_NONE
        list.addCSSClass("oneroot-duplicates")
        let scroller = ScrolledWindow(child: list)
        scroller.vexpand = true
        stack.addNamed(scroller, name: "list")
        stack.addNamed(emptyPage, name: "empty")
        stack.vexpand = true

        keepOldest.tooltipText = "In every set, keep the oldest copy and mark the rest"
        keepNewest.tooltipText = "In every set, keep the newest copy and mark the rest"
        clearButton.tooltipText = "Unmark everything"
        trashButton.addCSSClass(.destructiveAction)
        trashButton.tooltipText = "Move the marked files to the Trash (Ctrl+Z in a file window puts them back)"
        let spacer = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        spacer.hexpand = true
        let footer = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        footer.marginStart = 12
        footer.marginEnd = 12
        footer.marginTop = 8
        footer.marginBottom = 8
        footer.append(keepOldest)
        footer.append(keepNewest)
        footer.append(clearButton)
        footer.append(spacer)
        footer.append(trashButton)

        let toolbar = ToolbarView()
        toolbar.addTopBar(HeaderBar())
        let body = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        body.append(header)
        body.append(Separator(orientation: GTK_ORIENTATION_HORIZONTAL))
        body.append(stack)
        toolbar.setContent(body)
        toolbar.addBottomBar(footer)
        window.setContent(toolbar)
    }

    private func wire() {
        window.onCloseRequest { [weak self] in
            self?.viewModel.cancel()
            self?.onClose?()
            return false
        }
        scanButton.onClicked { [weak self] in
            guard let self else { return }
            if case .running = self.viewModel.state {
                self.viewModel.cancel()
            } else if !self.viewModel.roots.isEmpty {
                self.viewModel.start(self.viewModel.roots)
            }
        }
        keepOldest.onClicked { [weak self] in self?.viewModel.markAllButOne(keepingNewest: false) }
        keepNewest.onClicked { [weak self] in self?.viewModel.markAllButOne(keepingNewest: true) }
        clearButton.onClicked { [weak self] in self?.viewModel.clearMarks() }
        trashButton.onClicked { [weak self] in
            guard let self else { return }
            self.viewModel.trashMarked()
        }

        let viewModel = self.viewModel
        watches.append(ObservationWatch.watch({ (viewModel.state, viewModel.roots) }) { [weak self] _ in self?.refresh() })
        watches.append(ObservationWatch.watch({ viewModel.groups.map(\.id) }) { [weak self] _ in self?.rebuildRows() })
        watches.append(ObservationWatch.watch({ viewModel.marked }) { [weak self] _ in self?.marksChanged() })
        watches.append(ObservationWatch.watch({ viewModel.errorMessage }) { [weak self] message in
            guard let self, let message else { return }
            Dialogs.showError("Find Duplicates", message, parent: self.window)
            self.viewModel.errorMessage = nil
        })
    }

    // MARK: Refreshing

    private var rootNames: String {
        viewModel.roots.map { "\u{201C}\($0.lastPathComponent.isEmpty ? "/" : $0.lastPathComponent)\u{201D}" }.joined(separator: " and ")
    }

    private func refresh() {
        titleLabel.text = viewModel.roots.isEmpty ? "Find Duplicates" : "Duplicates in \(rootNames)"
        titleLabel.tooltipText = viewModel.roots.map(\.path).joined(separator: "\n")
        let running: Bool
        if case .running = viewModel.state { running = true } else { running = false }
        spinner.visible = running
        scanButton.label = running ? "Cancel" : "Scan Again"
        scanButton.sensitive = running || !viewModel.roots.isEmpty
        summaryLabel.text = summary
        updateEmptyState()
        marksChanged()
    }

    private var summary: String {
        switch viewModel.state {
        case .idle:
            return viewModel.roots.isEmpty
                ? "Choose Find Duplicates in a file window to look in its folder."
                : "Stopped."
        case .running(.scanning(let files)):
            return "Looking at \(files) files\u{2026}"
        case .running(.comparing(let done, let total)):
            return "Comparing files of the same size: \(done) of \(total)\u{2026}"
        case .failed(let message):
            return message
        case .done:
            guard !viewModel.groups.isEmpty else {
                return "No duplicates found. Subfolders were included; empty files aren\u{2019}t checked."
            }
            let count = viewModel.groups.count
            return "\(count) \(count == 1 ? "set" : "sets") of identical files \u{00B7} \(Formatting.size(viewModel.reclaimable)) could be freed"
        }
    }

    private func updateEmptyState() {
        if !viewModel.groups.isEmpty {
            stack.visibleChildName = "list"
            return
        }
        switch viewModel.state {
        case .running:
            emptyPage.iconName = "edit-find-symbolic"
            emptyPage.title = "Scanning\u{2026}"
            emptyPage.description = nil
        case .done:
            emptyPage.iconName = "object-select-symbolic"
            emptyPage.title = "No Duplicates"
            emptyPage.description = "No two files here have the same contents."
        case .failed(let message):
            emptyPage.iconName = "dialog-warning-symbolic"
            emptyPage.title = "Couldn\u{2019}t Scan"
            emptyPage.description = message
        case .idle:
            emptyPage.iconName = "edit-copy-symbolic"
            emptyPage.title = "Find Duplicates"
            emptyPage.description = "Use Find Duplicates from a file window\u{2019}s menu (Ctrl+Shift+D)."
        }
        stack.visibleChildName = "empty"
    }

    /// Enabling and the label of the footer buttons, from the marks.
    private func marksChanged() {
        let hasGroups = !viewModel.groups.isEmpty
        keepOldest.sensitive = hasGroups
        keepNewest.sensitive = hasGroups
        clearButton.sensitive = !viewModel.marked.isEmpty
        trashButton.sensitive = !viewModel.marked.isEmpty
        trashButton.label = viewModel.marked.isEmpty
            ? "Move to Trash"
            : "Move \(viewModel.marked.count) to Trash (\(Formatting.size(viewModel.markedSize)))"
        syncChecks()
    }

    // MARK: Rows

    private var checks: [(check: CheckButton, file: DuplicateFile, group: DuplicateGroup)] = []

    private func rebuildRows() {
        isRebuilding = true
        list.removeAll()
        checks = []
        for group in viewModel.groups {
            list.append(headerRow(group))
            for file in group.files { list.append(fileRow(file, in: group)) }
        }
        isRebuilding = false
        syncChecks()
        refresh()
    }

    private func headerRow(_ group: DuplicateGroup) -> ListBoxRow {
        let label = Label("\(group.files.count) copies \u{00B7} \(Formatting.size(group.size)) each")
        label.xalign = 0
        label.addCSSClass("heading")
        label.marginStart = 14
        label.marginTop = 8
        label.marginBottom = 4
        let row = ListBoxRow()
        row.child = label
        row.activatable = false
        row.selectable = false
        return row
    }

    private func fileRow(_ file: DuplicateFile, in group: DuplicateGroup) -> ListBoxRow {
        let check = CheckButton()
        check.setAccessibleLabel("Move \(file.url.lastPathComponent) to the Trash")
        check.onToggled { [weak self] in
            guard let self, !self.isRebuilding else { return }
            if self.viewModel.isMarked(file) != check.active { self.viewModel.toggle(file, in: group) }
        }
        checks.append((check, file, group))

        let icon = Image()
        FileIcons.set(icon, toFileAt: file.url)
        icon.pixelSize = 16
        let name = Label(file.url.lastPathComponent)
        name.xalign = 0
        name.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        let place = Label(location(of: file.url))
        place.xalign = 0
        place.ellipsize = PANGO_ELLIPSIZE_START
        place.addCSSClass(.dimLabel)
        place.addCSSClass("caption")
        let text = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 1)
        text.hexpand = true
        text.append(name)
        text.append(place)
        let date = Label(Formatting.date(file.modified))
        date.addCSSClass(.dimLabel)
        date.addCSSClass("caption")

        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        box.marginStart = 14
        box.marginEnd = 14
        box.marginTop = 4
        box.marginBottom = 4
        box.append(check)
        box.append(icon)
        box.append(text)
        box.append(date)

        let row = ListBoxRow()
        row.child = box
        row.tooltipText = file.url.path
        row.activatable = true

        let double = GestureClick()
        double.button = 1
        double.onPressed { [weak self] _, count, _ in
            if count == 2 { self?.open(file.url) }
        }
        row.addController(double)
        let right = GestureClick()
        right.button = 3
        right.onPressed { [weak self, weak row] _, _, _ in
            guard let self, let row else { return }
            self.showMenu(for: file.url, anchor: row)
        }
        row.addController(right)
        return row
    }

    /// Checks and the can't-mark-the-last-copy rule, from the view model.
    private func syncChecks() {
        isRebuilding = true
        for entry in checks {
            let marked = viewModel.isMarked(entry.file)
            if entry.check.active != marked { entry.check.active = marked }
            let allowed = viewModel.canMark(entry.file, in: entry.group)
            entry.check.sensitive = allowed
            entry.check.tooltipText = allowed ? "Move to the Trash" : "One copy always stays"
        }
        isRebuilding = false
    }

    /// The file's folder relative to the scanned folder it's in, or its full
    /// path.
    private func location(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        for root in viewModel.roots {
            let rootPath = root.resolvingSymlinksInPath().path
            if folder == rootPath { return root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent }
            if folder.hasPrefix(rootPath + "/") { return root.lastPathComponent + folder.dropFirst(rootPath.count) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    // MARK: Actions

    private func open(_ url: URL) {
        var error: UnsafeMutablePointer<GError>?
        if g_app_info_launch_default_for_uri(url.absoluteString, nil, &error) == 0 {
            let message = error.map { String(cString: $0.pointee.message) } ?? "No app is set to open it."
            if let error { g_error_free(error) }
            Dialogs.showError("Couldn\u{2019}t Open \u{201C}\(url.lastPathComponent)\u{201D}", message, parent: window)
        }
    }

    /// The file the right-click menu acts on.
    private var menuURL: URL?
    private var menuPopover: PopoverMenu?

    private func installMenuActions() {
        window.addAction(SimpleAction(name: "dup-open") { [weak self] in
            if let url = self?.menuURL { self?.open(url) }
        })
        window.addAction(SimpleAction(name: "dup-show") { [weak self] in
            if let url = self?.menuURL { self?.onShowInFolder?(url.deletingLastPathComponent()) }
        })
        window.addAction(SimpleAction(name: "dup-copy-path") { [weak self] in
            guard let url = self?.menuURL, let display = gdk_display_get_default(),
                  let clipboard = gdk_display_get_clipboard(display) else { return }
            gdk_clipboard_set_text(clipboard, url.path)
        })
    }

    private func showMenu(for url: URL, anchor: Widget) {
        menuURL = url
        let menu = GMenuRef()
        menu.append("Open", action: "win.dup-open")
        menu.append("Show in Folder", action: "win.dup-show")
        menu.append("Copy Path", action: "win.dup-copy-path")
        menuPopover?.unparent()
        guard let raw = gtk_popover_menu_new_from_model(menu.menuModelPointer) else { return }
        let object = UnsafeMutableRawPointer(raw)
        g_object_ref_sink(object)
        let popover = PopoverMenu(borrowing: object)
        g_object_unref(object)
        popover.setParent(anchor)
        _ = popover.popup()
        menuPopover = popover
    }
}
