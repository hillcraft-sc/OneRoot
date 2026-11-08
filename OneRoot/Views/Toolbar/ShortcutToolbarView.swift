import SwiftUI

/// The header of the file-list card, in two rows: Back / Forward / Up and
/// the path; then a selection-aware command row (see `commandRow`): New
/// — or, with items selected, their actions — a Paste chip when the
/// clipboard holds files, and Sort, Grid/List, Dual Pane, and More; then,
/// while the list is filtered, the filter chips (`FolderFilterBar`). Acts on
/// `viewModel.selectedNodes`, which the file views keep updated.
struct ShortcutToolbarView: View {
    var viewModel: FileListViewModel
    var layout: WindowLayoutModel
    /// The Workspace the tab is in, if any — the filter row then offers
    /// Search Workspace.
    var workspace: Workspace?
    let isDualPane: Bool
    let onToggleDualPane: () -> Void
    /// Compare Panes; shown while Dual Pane is on.
    var isComparing = false
    var onComparePanes: () -> Void = {}
    /// Re-reads both panes and the folder tree (⌘R).
    let onRefresh: () -> Void
    private var folderSizePreferences = FolderSizePreferenceStore.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What you last copied or cut in OneRoot, for the Paste chip.
    private var clipboard = ClipboardTracker.shared

    private var selection: [FileNode] { viewModel.selectedNodes }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NavigationButtons(viewModel: viewModel, onRefresh: onRefresh)
                AddressBarView(viewModel: viewModel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider().opacity(0.6)
            // With labels when they fit; icons only (with tooltips) when the
            // window is too narrow for them.
            ViewThatFits(in: .horizontal) {
                contextBar(showsLabels: true, compact: false)
                contextBar(showsLabels: false, compact: false)
                contextBar(showsLabels: false, compact: true)
            }
            .menuStyle(.borderlessButton)
            .task { await watchPasteboard() }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            if viewModel.showsAllFilesInSubfolders {
                Divider().opacity(0.6)
                FlatViewBar(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .transition(.opacity)
            }
            if viewModel.filter.hasFilters {
                Divider().opacity(0.6)
                FolderFilterBar(viewModel: viewModel, workspace: workspace)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: viewModel.filter.hasFilters)
    }

    /// New, the everyday edit commands in plain sight, then sorting and
    /// views, Dual Pane, and More for the rest.
    /// The **Context Bar**: calm until there's something to act on — New on
    /// the left, view controls on the right. Selecting items swaps New for a strip of the
    /// actions that apply to them; a Paste chip appears whenever the
    /// clipboard holds files. `showsLabels`/`compact` step the words off as
    /// the window narrows.
    private func contextBar(showsLabels: Bool, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if selection.isEmpty {
                    newMenu(compact: compact)
                        .transition(.opacity)
                } else {
                    SelectionStrip(
                        viewModel: viewModel,
                        selection: selection,
                        showsLabels: showsLabels,
                        showsCalculateSize: !folderSizePreferences.calculateAll,
                        accent: theme.accentColor
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
                }
            }
            .tint(.primary)
            Spacer(minLength: 8)
            // On the right, so it stays put however wide the left side is.
            if let pending = clipboard.pending {
                pasteChip(pending, compact: compact)
                    .transition(.opacity)
            }
            Group {
                sortMenu(compact: compact)
                viewOptionsMenu(compact: compact)
            }
            .tint(.primary)
            viewSwitcher(compact: true)
            dualPaneToggle(showsLabel: false)
            if isDualPane {
                Button(action: onComparePanes) {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(BarButtonStyle(isOn: isComparing))
                .help("Compare Panes: show what\u{2019}s newer, missing, or different in each folder")
                .accessibilityLabel("Compare Panes")
                .accessibilityValue(isComparing ? "On" : "Off")
            }
            Group {
                moreMenu(compact: compact)
            }
            .tint(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection.isEmpty)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: clipboard.pending)
    }

    /// "Paste 2 items" after a Copy, "Move 2 items here" after a Cut.
    private func pasteChip(_ pending: ClipboardTracker.Pending, compact: Bool) -> some View {
        let items = pending.count == 1 ? "1 item" : "\(pending.count) items"
        let title = pending.operation == .cut ? "Move \(items) here" : "Paste \(items)"
        return Button {
            viewModel.paste()
        } label: {
            Label(compact ? "\(pending.count)" : title, systemImage: pending.operation == .cut ? "arrow.down.doc" : "doc.on.clipboard")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
        }
        .buttonStyle(BarButtonStyle())
        .background(Capsule().strokeBorder(theme.separatorColor))
        .help("\(title) (⌘V)")
        .accessibilityLabel(title)
    }

    /// Checks the clipboard's change count once a second (cheap), so the
    /// Paste chip goes away once something else replaces what you copied.
    private func watchPasteboard() async {
        while !Task.isCancelled {
            clipboard.refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Two folders side by side in this card (⌘\).
    private func dualPaneToggle(showsLabel: Bool) -> some View {
        Button(action: onToggleDualPane) {
            if showsLabel {
                Label("Dual Pane", systemImage: "rectangle.split.2x1")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13))
                    .padding(.horizontal, 4)
            } else {
                Image(systemName: "rectangle.split.2x1")
            }
        }
        .buttonStyle(BarButtonStyle(isOn: isDualPane))
        .help("Dual Pane (⌘\\)")
        .accessibilityLabel("Dual Pane")
        .accessibilityValue(isDualPane ? "On" : "Off")
    }

    /// Grid / List, as one segmented control — remembered per folder.
    @ViewBuilder
    private func viewSwitcher(compact: Bool) -> some View {
        if compact {
            viewPicker.labelStyle(.iconOnly)
        } else {
            viewPicker.labelStyle(.titleAndIcon)
        }
    }

    private var viewPicker: some View {
        // The segmented control sets its selection while SwiftUI is still
        // updating the view, so the change waits a tick — publishing it
        // right away is "publishing changes from within view updates".
        Picker("View", selection: Binding(
            get: { viewModel.viewMode },
            set: { mode in DispatchQueue.main.async { viewModel.setViewMode(mode) } }
        )) {
            Label("Grid", systemImage: "square.grid.2x2").tag(FileViewMode.icons)
            Label("List", systemImage: "list.bullet").tag(FileViewMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("View as Grid (⌘1) or List (⌘2)")
    }

    /// Everything else: the edit commands, the less common actions, and
    /// view options.
    /// Things to do with the folder you're in — whatever's selected.
    private func moreMenu(compact: Bool) -> some View {
        Menu {
            Button("Copy Folder Path") {
                if let folder = viewModel.currentDirectory { viewModel.copyPaths([folder]) }
            }
            Button("Open Folder in Terminal") {
                if let folder = viewModel.currentDirectory { openInTerminal(folder) }
            }
            Button("Find Duplicates\u{2026}") {
                guard let folder = viewModel.currentDirectory else { return }
                DuplicatesHandoffCenter.shared.hand([folder])
                openWindow(id: OneRootApp.duplicatesWindowID)
            }
            .disabled(viewModel.currentDirectory == nil)
            if let folder = viewModel.currentDirectory {
                AddToWorkspaceMenu(folder: folder)
            }
            Divider()
            Button("New Folder…") { viewModel.promptForNewFolder() }
            Button("New File…") { viewModel.promptForNewFile() }
        } label: {
            ToolbarMenuLabel(title: "More", systemImage: "ellipsis.circle", showsTitle: !compact)
        }
        .disabled(viewModel.currentDirectory == nil)
        .fixedSize()
        .help("This folder: copy its path, open it in Terminal, add it to a Workspace")
    }

    /// View ▾ — panes, hidden files, folder sizes, and columns.
    private func viewOptionsMenu(compact: Bool) -> some View {
        Menu {
            viewOptionItems
        } label: {
            ToolbarMenuLabel(title: "View", systemImage: "slider.horizontal.3", showsTitle: !compact)
        }
        .fixedSize()
        .help("View options")
    }

    private func newMenu(compact: Bool) -> some View {
        Menu {
            Button("New Folder") { viewModel.promptForNewFolder() }
            Button("New Folder and Open") { viewModel.promptForNewFolderAndOpen() }
            Button("New File") { viewModel.promptForNewFile() }
        } label: {
            ToolbarMenuLabel(title: "New", systemImage: "plus", showsTitle: !compact)
        }
        .fixedSize()
        // Recents and Shared aren't folders: nothing can be made there.
        .disabled(viewModel.currentDirectory == nil)
    }

    /// Combines "Sort by" and "Group by" in one dropdown, matching how
    /// Explorer's own Sort menu bundles both rather than giving grouping
    /// its own separate toolbar icon.
    private func sortMenu(compact: Bool) -> some View {
        Menu {
            Section("Sort By") {
                ForEach(FileColumn.allCases, id: \.self) { column in
                    Button {
                        viewModel.setSort(field: column)
                    } label: {
                        if viewModel.sortField == column {
                            Label(column.title, systemImage: viewModel.sortDirection == .ascending ? "arrow.up" : "arrow.down")
                        } else {
                            Text(column.title)
                        }
                    }
                }
            }
            Section("Group By") {
                groupByButton("None", nil)
                groupByButton("Name", .name)
                groupByButton("Type", .kind)
                groupByButton("Date Modified", .dateModified)
                groupByButton("Size", .size)
                groupByButton("Tags", .tags)
            }
        } label: {
            ToolbarMenuLabel(title: "Sort", systemImage: "arrow.up.arrow.down", showsTitle: !compact)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func groupByButton(_ title: String, _ field: FileColumn?) -> some View {
        Button {
            viewModel.setGroupBy(field)
        } label: {
            if viewModel.groupBy == field {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// Panes, hidden files, folder sizes, and the columns — the file list's
    /// column-header menu, in a more discoverable spot.
    @ViewBuilder
    private var viewOptionItems: some View {
        Group {
            Button {
                layout.toggle(\.showsInspector)
            } label: {
                if layout.layout.showsInspector {
                    Label("Inspector", systemImage: "checkmark")
                } else {
                    Text("Inspector")
                }
            }
            // A one-off for this view; making it automatic is a setting
            // (Settings ▸ General), and then this isn't needed.
            if !folderSizePreferences.calculateAll {
                Button("Calculate Folder Sizes") { viewModel.calculateFolderSizesInView() }
                    .disabled(!viewModel.items.contains { $0.isDirectory && !$0.isPackage })
            }
            Button {
                viewModel.setShowsAllFilesInSubfolders(!viewModel.showsAllFilesInSubfolders)
            } label: {
                if viewModel.showsAllFilesInSubfolders {
                    Label("Show All Files in Subfolders", systemImage: "checkmark")
                } else {
                    Text("Show All Files in Subfolders")
                }
            }
            .disabled(viewModel.currentDirectory == nil)
            Button {
                viewModel.toggleShowHiddenFiles()
            } label: {
                if viewModel.showHiddenFiles {
                    Label("Hide Hidden Files", systemImage: "checkmark")
                } else {
                    Text("Show Hidden Files")
                }
            }
            Divider()
            ForEach(FileColumn.allCases, id: \.self) { column in
                // `.name` is always visible and can't be toggled; its row
                // stands in as a "Columns" heading.
                let title = column == .name ? "Columns" : column.title
                Button {
                    viewModel.toggleColumn(column)
                } label: {
                    if viewModel.visibleColumns.contains(column) {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
                .disabled(!column.isRemovable)
            }
        }
    }
}

/// "New ⌄" / "Sort ⌄" — a labeled dropdown instead
/// of a bare icon, matching Explorer's command bar. The disclosure chevron
/// is the system's own `Menu` indicator, not custom-drawn: a same-view
/// Image placed after the icon/title here is silently dropped by AppKit's
/// borderless-menu-button chrome, which sizes itself off its own content
/// metrics rather than SwiftUI's layout — same reason the icon can't be
/// sized with `.font(size:)` (see `scaleEffect` below).
private struct ToolbarMenuLabel: View {
    let title: String
    let systemImage: String?
    var showsTitle = true

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.primary)
            }
            if showsTitle || systemImage == nil {
                Text(title)
                    .font(.system(size: 13))
            }
        }
        .accessibilityLabel(title)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

/// The Context Bar's selection strip — "2 selected ✕ │ Copy  Cut  Rename
/// Share  (Size)  Compress  (Extract)  (Quick Actions ▾)  Copy Path
/// Terminal  Trash" in a soft
/// accent-tinted
/// capsule — what you can do with the selection, right where you look.
private struct SelectionStrip: View {
    var viewModel: FileListViewModel
    let selection: [FileNode]
    let showsLabels: Bool
    let showsCalculateSize: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(selection.count == 1 ? "1 selected" : "\(selection.count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.leading, 8)
                .accessibilityAddTraits(.isHeader)
            Button {
                viewModel.clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(BarButtonStyle())
            .help("Deselect All")
            .accessibilityLabel("Deselect All")
            Divider().frame(height: 14).padding(.horizontal, 2)
            action("Copy", "doc.on.doc") { viewModel.copySelection(selection) }
            action("Cut", "scissors") { viewModel.cutSelection(selection) }
            action("Rename", "pencil") {
                if selection.count > 1 {
                    viewModel.promptBatchRename(selection)
                } else if let node = selection.first {
                    viewModel.promptRename(node)
                }
            }
            ShareLink(items: selection.map(\.url)) {
                label("Share", "square.and.arrow.up")
            }
            .buttonStyle(BarButtonStyle())
            .help("Share")
            if showsCalculateSize, selection.contains(where: { $0.isDirectory && !$0.isPackage }) {
                action("Size", "scalemass", help: "Calculate Size") { viewModel.calculateFolderSizes(selection) }
            }
            action("Compress", "archivebox") { viewModel.compressSelection(selection) }
            // Only for archives OneRoot can open, so it isn't a dead button.
            if viewModel.canExtract(selection) {
                action("Extract", "arrow.up.bin") { viewModel.extractSelection(selection) }
            }
            let quickActions = viewModel.quickActionOptions(for: selection)
            if !quickActions.isEmpty {
                quickActionsMenu(quickActions)
            }
            action(selection.count > 1 ? "Copy Paths" : "Copy Path", "link") {
                viewModel.copyPaths(selection.map(\.url))
            }
            action("Terminal", "terminal", help: "Open in Terminal") {
                if let node = selection.first {
                    openInTerminal(node.isDirectory && !node.isPackage ? node.url : node.url.deletingLastPathComponent())
                }
            }
            action("Trash", "trash", isDestructive: true) {
                if TrashConfirmation.confirm(selection.map(\.name)) {
                    viewModel.moveToTrash(selection)
                }
            }
        }
        .padding(.trailing, 2)
        .background(Capsule().fill(accent.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for the selection")
    }

    /// Quick Actions ▾ — only for selections something applies to (images,
    /// PDFs). Ones that apply to part of the selection are disabled, with
    /// the reason in place of their name.
    private func quickActionsMenu(_ options: [QuickActionOption]) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    viewModel.promptQuickAction(option.action, for: selection)
                } label: {
                    if let reason = option.unavailableReason {
                        Text("\(option.action.menuTitle) \u{2014} \(reason)")
                    } else {
                        Label(option.action.menuTitle, systemImage: option.action.systemImage)
                    }
                }
                .disabled(!option.isAvailable)
            }
        } label: {
            label("Quick Actions", "wand.and.stars")
        }
        .fixedSize()
        .help("Resize or convert images, combine into a PDF, convert text, Markdown, and HTML")
        .accessibilityLabel("Quick Actions")
    }

    private func action(_ title: String, _ systemImage: String, help: String? = nil, isDestructive: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            label(title, systemImage)
        }
        .buttonStyle(BarButtonStyle(isDestructive: isDestructive))
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }

    @ViewBuilder
    private func label(_ title: String, _ systemImage: String) -> some View {
        if showsLabels {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12))
                .padding(.horizontal, 3)
        } else {
            Image(systemName: systemImage)
        }
    }
}
