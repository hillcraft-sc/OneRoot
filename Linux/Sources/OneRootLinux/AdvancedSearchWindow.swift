import Adwaita
import CAdwaita
import Foundation
import Observation
@testable import OneRoot

/// Advanced Search: a recursive, streaming search of a folder (or the whole
/// file system) by name or file contents, narrowed with the same filter
/// chips as a folder's — the GTK counterpart of the Mac's AdvancedSearchView
/// over the shared `SearchViewModel` and `SearchService`. Its own window, so
/// a long search doesn't hold up browsing.
@MainActor
final class AdvancedSearchWindow {
    let window: ApplicationWindow
    let viewModel: SearchViewModel
    /// Shows a result in a file window: its folder, in a new tab.
    var onShowInFolder: ((URL) -> Void)?
    /// The window was closed.
    var onClose: (() -> Void)?

    private let patternEntry = Entry()
    private let nameModeButton = ToggleButton(label: "Name & Metadata")
    private let contentsModeButton = ToggleButton(label: "File Contents")
    private let matchDropDown = DropDown(strings: SearchPatternMode.allCases.map(\.title))
    private var regexButton: Button!
    private let caseCheck = CheckButton(label: "Match case")
    private let hiddenCheck = CheckButton(label: "Include hidden files")
    private let searchButton = Button(label: "Search")
    private let rootLabel = Label("")
    private let statusLabel = Label("")
    private let errorLabel = Label("")
    private let showButton = Button(label: "Show in Folder")
    private let searchMenuButton = MenuButton()
    private let exportButton = MenuButton()
    private let savedQueries = SavedSearchQueriesService()
    private var queries: [SavedSearchQuery] = []
    private let store = ListStore()
    private let selection: SingleSelection
    private let columnView: ColumnView
    private let stack = Stack()
    private let emptyPage = StatusPage()
    private var matchColumn: ColumnViewColumn?
    private var chipRow: ChipRow!
    private let chipHost = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private var rows: [SearchResult] = []
    private var watches: [ObservationWatch] = []
    private var isSyncing = false
    private var hasSearched = false

    private static let contentPatternModes: [SearchPatternMode] = [.contains, .regex]

    init(application: Application, root: URL) {
        window = ApplicationWindow(application: application)
        window.title = "Advanced Search"
        window.defaultWidth = 900
        window.defaultHeight = 640
        viewModel = SearchViewModel(initialRoot: root)
        selection = SingleSelection(model: store)
        selection.autoselect = false
        selection.canUnselect = true
        columnView = ColumnView(model: selection)
        columnView.showColumnSeparators = false
        columnView.addCSSClass("oneroot-file-list")

        chipRow = ChipRow(source: FilterSource(
            criteria: { [weak self] in self?.viewModel.criteria ?? SearchCriteria(root: root) },
            update: { [weak self] in self?.criteriaEdited($0) },
            context: .advancedSearch
        ), host: chipHost)

        buildLayout()
        buildColumns()
        wire()
        refreshAll()
    }

    func present() {
        window.present()
        _ = patternEntry.grabFocus()
    }

    // MARK: Layout

    private func buildLayout() {
        let modes = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        modes.addCSSClass(.linked)
        contentsModeButton.setGroup(nameModeButton)
        nameModeButton.active = true
        modes.append(nameModeButton)
        modes.append(contentsModeButton)
        modes.halign = GTK_ALIGN_START

        patternEntry.hexpand = true
        patternEntry.setAccessibleLabel("Text to search for")
        searchButton.addCSSClass(.suggestedAction)
        let patternRow = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        patternRow.append(patternEntry)
        patternRow.append(matchDropDown)
        regexButton = SearchInputHelpers.regexSuggestionsButton { [weak self] pattern in
            self?.viewModel.criteria.pattern = pattern
        }
        regexButton.visible = false
        patternRow.append(regexButton)
        patternRow.append(searchButton)

        let optionsRow = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 16)
        optionsRow.append(caseCheck)
        optionsRow.append(hiddenCheck)

        let rootRow = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        let rootTitle = Label("Search in:")
        rootLabel.addCSSClass(.dimLabel)
        rootLabel.ellipsize = PANGO_ELLIPSIZE_START
        rootLabel.xalign = 0
        rootLabel.hexpand = true
        let choose = Button(label: "Choose\u{2026}")
        choose.onClicked { [weak self] in self?.chooseRoot() }
        let volume = Button(label: "Entire File System")
        volume.onClicked { [weak self] in self?.setRoot(URL(fileURLWithPath: "/", isDirectory: true)) }
        rootRow.append(rootTitle)
        rootRow.append(rootLabel)
        rootRow.append(choose)
        rootRow.append(volume)

        let addContent = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        addContent.append(Image(iconName: "list-add-symbolic"))
        addContent.append(Label("Add Filter"))
        let add = Button()
        add.child = addContent
        add.onClicked { [weak self, weak add] in
            guard let self, let add else { return }
            self.chipRow.showMenu(anchor: add)
        }
        let chipLine = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        chipLine.append(chipRow.widget)
        chipLine.append(add)
        chipHost.append(chipLine)

        let form = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        form.marginStart = 12
        form.marginEnd = 12
        form.marginTop = 10
        form.marginBottom = 8
        form.append(modes)
        form.append(patternRow)
        form.append(optionsRow)
        form.append(rootRow)
        form.append(chipHost)

        let scroller = ScrolledWindow(child: columnView)
        scroller.vexpand = true
        emptyPage.addCSSClass("compact")
        stack.addNamed(scroller, name: "list")
        stack.addNamed(emptyPage, name: "empty")
        stack.vexpand = true

        statusLabel.xalign = 0
        statusLabel.hexpand = true
        statusLabel.ellipsize = PANGO_ELLIPSIZE_END
        statusLabel.addCSSClass(.dimLabel)
        statusLabel.addCSSClass("caption")
        errorLabel.addCSSClass(.error)
        errorLabel.addCSSClass("caption")
        errorLabel.ellipsize = PANGO_ELLIPSIZE_END
        showButton.tooltipText = "Show the selected result in its folder, in a new tab"
        let footer = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        footer.addCSSClass("oneroot-status")
        footer.append(statusLabel)
        footer.append(errorLabel)
        footer.append(showButton)

        searchMenuButton.label = "Saved & Scope"
        searchMenuButton.tooltipText = "Saved queries, search a Workspace, show as a Terminal command"
        searchMenuButton.setAccessibleLabel("Saved queries, Workspaces and Terminal command")
        exportButton.label = "Export\u{2026}"
        exportButton.tooltipText = "Save the results as CSV, text, Markdown or HTML"
        exportButton.setAccessibleLabel("Export results")
        exportButton.sensitive = false
        footer.append(exportButton)
        let header = HeaderBar()
        header.packEnd(searchMenuButton)
        let toolbar = ToolbarView()
        toolbar.addTopBar(header)
        let body = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        body.append(form)
        body.append(Separator(orientation: GTK_ORIENTATION_HORIZONTAL))
        body.append(stack)
        toolbar.setContent(body)
        toolbar.addBottomBar(footer)
        window.setContent(toolbar)
    }

    private func buildColumns() {
        func column(_ title: String, width: Int?, expand: Bool = false, align: Float = 0,
                    text: @escaping (SearchResult) -> String) -> ColumnViewColumn {
            let factory = SignalListItemFactory()
            factory.onSetup { item in
                let label = Label("")
                label.xalign = align
                label.ellipsize = PANGO_ELLIPSIZE_END
                item.child = label
            }
            factory.onBind { [weak self] item in
                guard let self, item.position < self.rows.count, let label = item.child?.cast(Label.self) else { return }
                label.text = text(self.rows[item.position])
            }
            let column = ColumnViewColumn(title: title, factory: factory)
            column.resizable = true
            if expand { column.expand = true }
            if let width { column.fixedWidth = width }
            columnView.appendColumn(column)
            return column
        }

        let nameFactory = SignalListItemFactory()
        nameFactory.onSetup { item in
            let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            let image = Image()
            image.pixelSize = 16
            let label = Label("")
            label.xalign = 0
            label.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            box.append(image)
            box.append(label)
            item.child = box
        }
        nameFactory.onBind { [weak self] item in
            guard let self, item.position < self.rows.count, let child = item.child,
                  let image = child.firstChild?.cast(Image.self), let label = child.lastChild?.cast(Label.self) else { return }
            let node = self.rows[item.position].node
            FileIcons.set(image, to: node)
            label.text = node.name
        }
        let name = ColumnViewColumn(title: "Name", factory: nameFactory)
        name.resizable = true
        name.fixedWidth = 240
        columnView.appendColumn(name)

        matchColumn = column("Match", width: nil, expand: true) { result in
            result.contentMatch.map { "\($0.lineNumber): \($0.snippet.trimmingCharacters(in: .whitespaces))" } ?? ""
        }
        _ = column("Location", width: 200) { $0.node.url.deletingLastPathComponent().path }
        _ = column("Size", width: 90, align: 1) { $0.node.isDirectory ? "" : ($0.node.size.map(Formatting.size) ?? "") }
        _ = column("Modified", width: 170) { Formatting.date($0.node.modificationDate) }
    }

    // MARK: Wiring

    private func wire() {
        window.onCloseRequest { [weak self] in
            self?.viewModel.cancel()
            self?.onClose?()
            return false
        }
        patternEntry.onChanged { [weak self] in
            guard let self, !self.isSyncing, self.viewModel.criteria.pattern != self.patternEntry.text else { return }
            self.viewModel.criteria.pattern = self.patternEntry.text
            self.updateSearchButton()
        }
        patternEntry.onActivate { [weak self] in self?.startOrCancel(startOnly: true) }
        searchButton.onClicked { [weak self] in self?.startOrCancel(startOnly: false) }
        nameModeButton.onToggled { [weak self] in
            guard let self, !self.isSyncing, self.nameModeButton.active else { return }
            self.setMode(.nameAndMetadata)
        }
        contentsModeButton.onToggled { [weak self] in
            guard let self, !self.isSyncing, self.contentsModeButton.active else { return }
            self.setMode(.contents)
        }
        matchDropDown.onSelectedChanged { [weak self] in
            guard let self, !self.isSyncing else { return }
            let modes = SearchPatternMode.allCases
            guard modes.indices.contains(self.matchDropDown.selected) else { return }
            self.viewModel.criteria.patternMode = modes[self.matchDropDown.selected]
        }
        caseCheck.onToggled { [weak self] in
            guard let self, !self.isSyncing else { return }
            self.viewModel.criteria.caseSensitive = self.caseCheck.active
        }
        hiddenCheck.onToggled { [weak self] in
            guard let self, !self.isSyncing else { return }
            self.viewModel.criteria.includeHidden = self.hiddenCheck.active
            if self.viewModel.isSearching, self.viewModel.canSearch { self.viewModel.start() }
        }
        columnView.onActivate { [weak self] position in self?.open(position) }
        selection.onSelectionChanged { [weak self] in self?.showButton.sensitive = self?.selectedResult != nil }
        showButton.onClicked { [weak self] in
            guard let result = self?.selectedResult else { return }
            self?.show(result)
        }
        showButton.sensitive = false
        installMenuActions()
        queries = savedQueries.load()
        rebuildMenus()
        watches.append(ObservationWatch.watch({ WorkspaceStore.shared.workspaces }, emitsInitialValue: false) { [weak self] _ in
            self?.rebuildMenus()
        })

        let viewModel = self.viewModel
        watches.append(ObservationWatch.watch({ viewModel.criteria }) { [weak self] _ in self?.criteriaChanged() })
        watches.append(ObservationWatch.watch({ viewModel.results.count }) { [weak self] _ in self?.reloadRows() })
        watches.append(ObservationWatch.watch({
            (viewModel.isSearching, viewModel.foldersScanned, viewModel.filesScanned,
             viewModel.filesSkipped, viewModel.errorMessage, viewModel.engine)
        }) { [weak self] _ in self?.updateStatus() })
        // Search Subfolders: a folder's filter, waiting for this window.
        watches.append(ObservationWatch.watch({ SearchHandoffCenter.shared.pending }) { [weak self] pending in
            guard let self, pending != nil else { return }
            self.viewModel.takeHandoff(from: .shared)
            self.hasSearched = true
            self.refreshAll()
        })
    }

    private func setMode(_ mode: SearchMode) {
        viewModel.criteria.mode = mode
        if mode == .contents, !Self.contentPatternModes.contains(viewModel.criteria.patternMode) {
            viewModel.criteria.patternMode = .contains
        }
        refreshAll()
    }

    /// A chip was edited or removed. A running search restarts when
    /// something other than the text changed, so results match the chips.
    private func criteriaEdited(_ new: SearchCriteria) {
        var before = viewModel.criteria
        var after = new
        before.pattern = ""
        after.pattern = ""
        viewModel.criteria = new
        if viewModel.isSearching, before != after, viewModel.canSearch { viewModel.start() }
    }

    private func startOrCancel(startOnly: Bool) {
        if viewModel.isSearching {
            if !startOnly { viewModel.cancel() }
            return
        }
        guard viewModel.canSearch else { return }
        hasSearched = true
        viewModel.start()
    }

    // MARK: Refreshing

    /// Controls from the criteria — after a hand-off, a mode change, or a
    /// new root.
    private func refreshAll() {
        criteriaChanged()
    }

    private func criteriaChanged() {
        let criteria = viewModel.criteria
        isSyncing = true
        if patternEntry.text != criteria.pattern { patternEntry.text = criteria.pattern }
        nameModeButton.active = criteria.mode == .nameAndMetadata
        contentsModeButton.active = criteria.mode == .contents
        matchDropDown.selected = SearchPatternMode.allCases.firstIndex(of: criteria.patternMode) ?? 0
        caseCheck.active = criteria.caseSensitive
        hiddenCheck.active = criteria.includeHidden
        isSyncing = false
        patternEntry.placeholderText = criteria.mode == .contents ? "Text to find" : "Name (optional)"
        regexButton.visible = criteria.patternMode == .regex
        matchColumn?.isVisible = criteria.mode == .contents
        if let name = criteria.workspaceName, criteria.searchRoots.count > 1 {
            rootLabel.text = "Workspace \u{201C}\(name)\u{201D} (\(criteria.searchRoots.count) folders)"
        } else {
            rootLabel.text = criteria.searchRoots.map(\.path).joined(separator: ", ")
        }
        rootLabel.tooltipText = rootLabel.text
        chipRow.rebuild()
        updateSearchButton()
        updateEmptyState()
    }

    private func updateSearchButton() {
        if viewModel.isSearching {
            searchButton.label = "Cancel"
            searchButton.removeCSSClass(.suggestedAction)
            searchButton.sensitive = true
        } else {
            searchButton.label = "Search"
            searchButton.addCSSClass(.suggestedAction)
            searchButton.sensitive = viewModel.canSearch
        }
    }

    private func updateStatus() {
        updateSearchButton()
        errorLabel.text = viewModel.errorMessage ?? ""
        errorLabel.visible = viewModel.errorMessage != nil
        let count = viewModel.results.count
        var text: String
        if viewModel.isSearching {
            text = "Searching\u{2026} \(count) found"
        } else if hasSearched {
            text = count == 1 ? "1 result" : "\(count) results"
        } else {
            text = ""
        }
        if hasSearched {
            text += " \u{00B7} scanned \(viewModel.foldersScanned) folders, \(viewModel.filesScanned) files"
            if viewModel.filesSkipped > 0 { text += ", skipped \(viewModel.filesSkipped) unreadable" }
            if case .spotlightIndex = viewModel.engine { text += " \u{00B7} index first" }
        }
        statusLabel.text = text
        updateEmptyState()
    }

    private func updateEmptyState() {
        if !rows.isEmpty {
            stack.visibleChildName = "list"
            return
        }
        if viewModel.isSearching {
            emptyPage.iconName = "system-search-symbolic"
            emptyPage.title = "Searching\u{2026}"
            emptyPage.description = nil
        } else if hasSearched {
            emptyPage.iconName = "system-search-symbolic"
            emptyPage.title = "No Results"
            emptyPage.description = "Nothing matches these criteria."
        } else {
            emptyPage.iconName = "system-search-symbolic"
            emptyPage.title = "Search"
            emptyPage.description = "Type a name or text, add filters, then press Enter."
        }
        stack.visibleChildName = "empty"
    }

    /// Results only grow during a search: new ones are added at the end
    /// instead of rebuilding the whole list; a new search starts over.
    private func reloadRows() {
        let results = viewModel.results
        let appendOnly = results.count >= rows.count
            && zip(rows, results).allSatisfy { $0.id == $1.id }
        let from = appendOnly ? rows.count : 0
        let removed = appendOnly ? 0 : UInt32(store.count)
        rows = results
        var placeholders: [gpointer?] = (from..<rows.count).map { _ in cadw_object_new(cadw_type_object()) }
        placeholders.withUnsafeMutableBufferPointer { buffer in
            g_list_store_splice(store.opaquePointer, UInt32(from), removed, buffer.baseAddress, UInt32(buffer.count))
        }
        for object in placeholders { g_object_unref(object) }
        exportButton.sensitive = !rows.isEmpty
        updateEmptyState()
        updateStatus()
    }

    // MARK: Results

    private var selectedResult: SearchResult? {
        let position = selection.selected
        return rows.indices.contains(position) ? rows[position] : nil
    }

    private func open(_ position: Int) {
        guard rows.indices.contains(position) else { return }
        let node = rows[position].node
        if node.isDirectory {
            show(rows[position])
            return
        }
        var error: UnsafeMutablePointer<GError>?
        if g_app_info_launch_default_for_uri(node.url.absoluteString, nil, &error) == 0 {
            let message = error.map { String(cString: $0.pointee.message) } ?? "No app is set to open it."
            if let error { g_error_free(error) }
            errorLabel.text = "Couldn't open \u{201C}\(node.name)\u{201D}: \(message)"
            errorLabel.visible = true
        }
    }

    private func show(_ result: SearchResult) {
        onShowInFolder?(result.node.isDirectory ? result.node.url : result.node.url.deletingLastPathComponent())
    }

    // MARK: Saved queries, Workspaces, Terminal command, Export

    private func installMenuActions() {
        window.addAction(SimpleAction(name: "save-query") { [weak self] in self?.promptSaveQuery() })
        window.addAction(SimpleAction(name: "load-query", parameterType: "s") { [weak self] parameter in
            guard let self, let id = parameter.stringValue, let query = self.queries.first(where: { $0.id.uuidString == id }) else { return }
            self.viewModel.criteria = query.criteria
            self.refreshAll()
        })
        window.addAction(SimpleAction(name: "delete-query", parameterType: "s") { [weak self] parameter in
            guard let self, let id = parameter.stringValue, let uuid = UUID(uuidString: id) else { return }
            self.queries = self.savedQueries.remove(id: uuid)
            self.rebuildMenus()
        })
        window.addAction(SimpleAction(name: "use-workspace", parameterType: "s") { [weak self] parameter in
            guard let self, let id = parameter.stringValue, let uuid = UUID(uuidString: id),
                  let workspace = WorkspaceStore.shared.workspace(uuid) else { return }
            self.useWorkspace(workspace)
        })
        window.addAction(SimpleAction(name: "terminal-command") { [weak self] in self?.showTerminalCommand() })
        window.addAction(SimpleAction(name: "export", parameterType: "s") { [weak self] parameter in
            guard let self, let raw = parameter.stringValue, let format = SearchResultExportFormat(rawValue: raw) else { return }
            self.export(format)
        })
    }

    private func rebuildMenus() {
        let menu = GMenuRef()
        let saved = GMenuRef()
        saved.append("Save Current Query\u{2026}", action: "win.save-query")
        let load = GMenuRef()
        let delete = GMenuRef()
        for query in queries {
            let item = GMenuItemRef(label: query.name, action: "win.load-query")
            item.setTargetValue(Variant.string(query.id.uuidString))
            load.appendItem(item)
            let remove = GMenuItemRef(label: query.name, action: "win.delete-query")
            remove.setTargetValue(Variant.string(query.id.uuidString))
            delete.appendItem(remove)
        }
        if !queries.isEmpty {
            saved.appendSection(nil, section: load)
            let deleteMenu = GMenuRef()
            deleteMenu.appendSubmenu("Delete", submenu: delete)
            saved.appendSection(nil, section: deleteMenu)
        }
        menu.appendSection("Saved Queries", section: saved)

        let workspaces = GMenuRef()
        for workspace in WorkspaceStore.shared.workspaces where !workspace.folders.isEmpty {
            let item = GMenuItemRef(label: workspace.name, action: "win.use-workspace")
            item.setTargetValue(Variant.string(workspace.id.uuidString))
            workspaces.appendItem(item)
        }
        menu.appendSection("Search a Workspace", section: workspaces)

        let other = GMenuRef()
        other.append("Show as Terminal Command\u{2026}", action: "win.terminal-command")
        menu.appendSection(nil, section: other)
        searchMenuButton.setMenuModel(menu)

        let exports = GMenuRef()
        for format in SearchResultExportFormat.allCases {
            let item = GMenuItemRef(label: format.title, action: "win.export")
            item.setTargetValue(Variant.string(format.rawValue))
            exports.appendItem(item)
        }
        exportButton.setMenuModel(exports)
    }

    private func promptSaveQuery() {
        Dialogs.promptName(heading: "Save Query", body: "Saves this search\u{2019}s filters so you can run it again later.",
                           initial: "Saved Search", confirm: "Save", selectsStem: false, parent: window) { [weak self] name in
            guard let self else { return }
            self.queries = self.savedQueries.upsert(SavedSearchQuery(name: name, criteria: self.viewModel.criteria))
            self.rebuildMenus()
        }
    }

    private func useWorkspace(_ workspace: Workspace) {
        guard let first = workspace.folders.first else { return }
        viewModel.criteria.root = first
        viewModel.criteria.additionalRoots = Array(workspace.folders.dropFirst())
        viewModel.criteria.workspaceName = workspace.name
    }

    private func showTerminalCommand() {
        let command = SearchCommandLineBuilder().command(for: viewModel.criteria)
        let dialog = Dialogs.alert(
            heading: "Terminal Command",
            body: "Run this in a terminal to repeat the search, or put it in a script.",
            responses: [("close", "Close"), ("copy", "Copy")], suggested: "copy")
        let label = Label(command)
        label.wrap = true
        label.xalign = 0
        label.addCSSClass("monospace")
        gtk_label_set_selectable(OpaquePointer(label.widgetPointer), 1)
        dialog.extraChild = label
        dialog.onResponse { response in
            guard response == "copy", let display = gdk_display_get_default(),
                  let clipboard = gdk_display_get_clipboard(display) else { return }
            gdk_clipboard_set_text(clipboard, command)
        }
        dialog.present(window)
    }

    /// Writes the results, as they are when the format is chosen, to a file
    /// the user names.
    private func export(_ format: SearchResultExportFormat) {
        let results = viewModel.results
        guard !results.isEmpty else { return }
        let mode = viewModel.criteria.mode
        let dialog = FileDialog()
        dialog.title = "Export Results"
        dialog.acceptLabel = "Export"
        dialog.modal = true
        dialog.initialName = "Search Results.\(format.fileExtension)"
        dialog.save(parent: window) { [weak self] result in
            guard case .success(let path?) = result else { return }
            let content = SearchResultExportService().export(results, mode: mode, format: format)
            do {
                try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            } catch {
                self?.errorLabel.text = "Couldn\u{2019}t save \u{201C}\((path as NSString).lastPathComponent)\u{201D}: \(error.localizedDescription)"
                self?.errorLabel.visible = true
            }
        }
    }

    // MARK: Search location

    private func setRoot(_ url: URL) {
        viewModel.criteria.root = url
        viewModel.criteria.additionalRoots = []
        viewModel.criteria.workspaceName = nil
    }

    private func chooseRoot() {
        let dialog = FileDialog()
        dialog.title = "Search In"
        dialog.acceptLabel = "Choose"
        dialog.modal = true
        dialog.selectFolder(parent: window) { [weak self] result in
            if case .success(let path?) = result { self?.setRoot(URL(fileURLWithPath: path, isDirectory: true)) }
        }
    }
}
