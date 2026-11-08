import SwiftUI

struct FileListView: View {
    @Bindable var viewModel: FileListViewModel
    /// In a split tab: the other pane, target of Copy/Move to Other Pane.
    var otherPane: FileListViewModel? = nil
    /// In a split tab: makes this pane the focused one.
    var onFocus: (() -> Void)? = nil
    var onNavigate: (_ url: URL, _ openInNewTab: Bool) -> Void

    @State private var renameText = ""
    @State private var newFolderName = "New Folder"
    @State private var newFileName = "New File"
    @State private var sshCopyFileURLs: [URL]?
    @AppStorage(FileViewMode.iconSizeKey) private var iconSize = FileViewMode.defaultIconSize

    var body: some View {
        Group {
            switch viewModel.viewMode {
            case .list:
                FileTableRepresentable(viewModel: viewModel, panes: panes, onNavigate: onNavigate, sshCopyFileURLs: $sshCopyFileURLs)
            case .icons:
                FileIconRepresentable(viewModel: viewModel, panes: panes, onNavigate: onNavigate, sshCopyFileURLs: $sshCopyFileURLs, iconSize: iconSize)
            }
        }
            .overlay { FileListStateOverlay(viewModel: viewModel) }
            .onChange(of: viewModel.pendingRenameNode?.url) { _, _ in
                if let node = viewModel.pendingRenameNode { renameText = node.name }
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.pendingBatchRenameNodes != nil },
                    set: { isPresented in if !isPresented { viewModel.pendingBatchRenameNodes = nil } }
                )
            ) {
                if let nodes = viewModel.pendingBatchRenameNodes {
                    BatchRenameView(urls: nodes.map(\.url)) { newNames in
                        viewModel.applyBatchRename(urls: nodes.map(\.url), newNames: newNames)
                        viewModel.pendingBatchRenameNodes = nil
                    } onCancel: {
                        viewModel.pendingBatchRenameNodes = nil
                    }
                }
            }
            .sheet(item: $viewModel.pendingQuickAction) { pending in
                QuickActionSheet(pending: pending) { request, plan in
                    viewModel.runQuickAction(request, plan: plan)
                } onCancel: {
                    viewModel.pendingQuickAction = nil
                }
            }
            .onChange(of: viewModel.pendingOpenInNewTabDirectory) { _, directory in
                guard let directory else { return }
                onNavigate(directory, true)
                viewModel.clearPendingOpenInNewTabDirectory()
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.pendingRestoreDestinationItemName != nil },
                    set: { isPresented in if !isPresented { viewModel.resolveRestoreDestination(nil) } }
                )
            ) {
                FileChooserView(
                    startingAt: FileManager.default.homeDirectoryForCurrentUser,
                    message: "OneRoot doesn't know where \"\(viewModel.pendingRestoreDestinationItemName ?? "this item")\" was trashed from — choose where to restore it",
                    chooseButtonTitle: "Restore"
                ) { url in
                    viewModel.resolveRestoreDestination(url)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { sshCopyFileURLs != nil },
                    set: { isPresented in if !isPresented { sshCopyFileURLs = nil } }
                )
            ) {
                if let sshCopyFileURLs {
                    CopyViaSSHView(fileURLs: sshCopyFileURLs)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.pendingArchiveDestinationItemName != nil },
                    set: { isPresented in if !isPresented { viewModel.resolveArchiveDestination(nil) } }
                )
            ) {
                FileChooserView(
                    startingAt: FileManager.default.homeDirectoryForCurrentUser,
                    canChooseFiles: false,
                    canChooseDirectories: true,
                    message: "Choose where to save \"\(viewModel.pendingArchiveDestinationItemName ?? "the archive")\"",
                    chooseButtonTitle: "Save"
                ) { url in
                    viewModel.resolveArchiveDestination(url)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.pendingExtractDestinationItemName != nil },
                    set: { isPresented in if !isPresented { viewModel.resolveExtractDestination(nil) } }
                )
            ) {
                FileChooserView(
                    startingAt: FileManager.default.homeDirectoryForCurrentUser,
                    canChooseFiles: false,
                    canChooseDirectories: true,
                    message: "Choose where to extract \"\(viewModel.pendingExtractDestinationItemName ?? "the archive")\"",
                    chooseButtonTitle: "Extract"
                ) { url in
                    viewModel.resolveExtractDestination(url)
                }
            }
            .alert(
                "Rename",
                isPresented: Binding(
                    get: { viewModel.pendingRenameNode != nil },
                    set: { isPresented in if !isPresented { viewModel.pendingRenameNode = nil } }
                ),
                actions: {
                    TextField("Name", text: $renameText)
                    Button("Rename") {
                        if let node = viewModel.pendingRenameNode {
                            viewModel.rename(node, to: renameText)
                        }
                        viewModel.pendingRenameNode = nil
                    }
                    Button("Cancel", role: .cancel) { viewModel.pendingRenameNode = nil }
                }
            )
            .alert(
                "New Folder",
                isPresented: Binding(
                    get: { viewModel.pendingNewFolderIntent != nil },
                    set: { isPresented in if !isPresented { viewModel.pendingNewFolderIntent = nil } }
                ),
                actions: {
                    TextField("Name", text: $newFolderName)
                    Button("Create") {
                        viewModel.createFolder(named: newFolderName)
                        newFolderName = "New Folder"
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.pendingNewFolderIntent = nil
                        newFolderName = "New Folder"
                    }
                }
            )
            .alert(
                "New File",
                isPresented: $viewModel.pendingNewFileIntent,
                actions: {
                    TextField("Name", text: $newFileName)
                    Button("Create") {
                        viewModel.createFile(named: newFileName)
                        newFileName = "New File"
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.pendingNewFileIntent = false
                        newFileName = "New File"
                    }
                }
            )
            .fileConflictPrompt(viewModel.pendingConflicts) { answer, id in
                viewModel.answerConflicts(answer, to: id)
            }
            .nameFixPrompt(viewModel.pendingNameFix) { answer, id in
                viewModel.answerNameFix(answer, to: id)
            }
    }

    private var panes: PaneWiring {
        PaneWiring(otherPane: otherPane, onFocus: onFocus)
    }
}

/// What a file view needs to know about being one half of a split tab.
private struct PaneWiring {
    let otherPane: FileListViewModel?
    let onFocus: (() -> Void)?
}

private struct FileTableRepresentable: NSViewRepresentable {
    @Bindable var viewModel: FileListViewModel
    let panes: PaneWiring
    var onNavigate: (_ url: URL, _ openInNewTab: Bool) -> Void
    @Binding var sshCopyFileURLs: [URL]?

    func makeCoordinator() -> FileTableController {
        let controller = FileTableController()
        // Only Quick Look requests made from now on — not one the view
        // model received before this table existed.
        controller.lastHandledQuickLookTrigger = viewModel.quickLookTrigger
        controller.lastHandledClearSelectionTrigger = viewModel.clearSelectionTrigger
        controller.lastHandledSelectionRequest = viewModel.selectionRequest
        return controller
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true // when columns are wider than the view
        scrollView.autohidesScrollers = true
        scrollView.documentView = context.coordinator.tableView
        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.items = viewModel.items
        context.coordinator.visibleColumns = viewModel.displayedColumns
        context.coordinator.groupBy = viewModel.groupBy
        context.coordinator.folderSizes = viewModel.folderSizes
        context.coordinator.calculatingFolderSizes = viewModel.calculatingFolderSizes
        context.coordinator.comparisonStatuses = viewModel.comparisonStatuses
        context.coordinator.updateSortIndicator(field: viewModel.sortField, direction: viewModel.sortDirection)
        context.coordinator.onSortChange = { field in viewModel.setSort(field: field) }
        context.coordinator.onToggleColumn = { column in viewModel.toggleColumn(column) }
        context.coordinator.onReorderColumns = { columns in viewModel.reorderColumns(columns) }
        context.coordinator.onSelectionChange = { nodes in viewModel.updateSelection(nodes) }
        context.coordinator.actions.wire(to: viewModel, panes: panes, onNavigate: onNavigate) { urls in
            requestSSHCopy(for: urls) { sshCopyFileURLs = $0 }
        }
        if context.coordinator.lastHandledQuickLookTrigger != viewModel.quickLookTrigger {
            context.coordinator.lastHandledQuickLookTrigger = viewModel.quickLookTrigger
            context.coordinator.actions.handleQuickLook()
        }
        if context.coordinator.lastHandledClearSelectionTrigger != viewModel.clearSelectionTrigger {
            context.coordinator.lastHandledClearSelectionTrigger = viewModel.clearSelectionTrigger
            context.coordinator.clearSelection()
        }
        if context.coordinator.lastHandledSelectionRequest != viewModel.selectionRequest {
            context.coordinator.lastHandledSelectionRequest = viewModel.selectionRequest
            context.coordinator.select(viewModel.requestedSelection)
        }
        if !context.coordinator.didRestoreInitialSelection {
            context.coordinator.didRestoreInitialSelection = true
            context.coordinator.select(Set(viewModel.selectedNodes.map(\.url)))
        }
    }
}

private struct FileIconRepresentable: NSViewRepresentable {
    @Bindable var viewModel: FileListViewModel
    let panes: PaneWiring
    var onNavigate: (_ url: URL, _ openInNewTab: Bool) -> Void
    @Binding var sshCopyFileURLs: [URL]?
    let iconSize: Double

    func makeCoordinator() -> FileIconController {
        let controller = FileIconController()
        controller.lastHandledQuickLookTrigger = viewModel.quickLookTrigger
        controller.lastHandledClearSelectionTrigger = viewModel.clearSelectionTrigger
        controller.lastHandledSelectionRequest = viewModel.selectionRequest
        return controller
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = context.coordinator.collectionView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.items = viewModel.items
        context.coordinator.iconSize = CGFloat(iconSize)
        context.coordinator.onSelectionChange = { nodes in viewModel.updateSelection(nodes) }
        context.coordinator.actions.wire(to: viewModel, panes: panes, onNavigate: onNavigate) { urls in
            requestSSHCopy(for: urls) { sshCopyFileURLs = $0 }
        }
        if context.coordinator.lastHandledQuickLookTrigger != viewModel.quickLookTrigger {
            context.coordinator.lastHandledQuickLookTrigger = viewModel.quickLookTrigger
            context.coordinator.actions.handleQuickLook()
        }
        if context.coordinator.lastHandledClearSelectionTrigger != viewModel.clearSelectionTrigger {
            context.coordinator.lastHandledClearSelectionTrigger = viewModel.clearSelectionTrigger
            context.coordinator.clearSelection()
        }
        if context.coordinator.lastHandledSelectionRequest != viewModel.selectionRequest {
            context.coordinator.lastHandledSelectionRequest = viewModel.selectionRequest
            context.coordinator.select(viewModel.requestedSelection)
        }
        if !context.coordinator.didRestoreInitialSelection {
            context.coordinator.didRestoreInitialSelection = true
            context.coordinator.select(Set(viewModel.selectedNodes.map(\.url)))
        }
    }
}

extension FileItemActions {
    /// Points every shared action at `viewModel` — called from each file
    /// view's `updateNSView`, so the list and the icon grid stay wired
    /// identically.
    fileprivate func wire(
        to viewModel: FileListViewModel,
        panes: PaneWiring,
        onNavigate: @escaping (_ url: URL, _ openInNewTab: Bool) -> Void,
        onCopyViaSSH: @escaping ([URL]) -> Void
    ) {
        onFocus = panes.onFocus
        if let otherPane = panes.otherPane {
            // Through this pane's own drop handling, so it gets the same
            // conflict prompt, progress window, and Undo as a drag would.
            onSendToOtherPane = { nodes, move in
                guard let destination = otherPane.currentDirectory else { return }
                viewModel.handleDrop(urls: nodes.map(\.url), into: destination, move: move)
            }
        } else {
            onSendToOtherPane = nil
        }
        onOpenFolder = { node, openInNewTab in onNavigate(node.url, openInNewTab) }
        onCopy = { nodes in viewModel.copySelection(nodes) }
        onDeselectAll = { viewModel.clearSelection() }
        onCut = { nodes in viewModel.cutSelection(nodes) }
        onPaste = { viewModel.paste() }
        onRename = { node in viewModel.promptRename(node) }
        onBatchRename = { nodes in viewModel.promptBatchRename(nodes) }
        onCalculateSize = { nodes in viewModel.calculateFolderSizes(nodes) }
        onMoveToTrash = { nodes in viewModel.moveToTrash(nodes) }
        onNewFolder = { viewModel.promptForNewFolder() }
        onNewFolderAndOpen = { viewModel.promptForNewFolderAndOpen() }
        onNewFolderHere = { node in viewModel.promptForNewFolderHere(in: node) }
        onNewFile = { viewModel.promptForNewFile() }
        onCopyPath = { node in viewModel.copyPath(node) }
        onDuplicate = { nodes in viewModel.duplicate(nodes) }
        onCopyNames = { nodes, includeExtension in viewModel.copyNames(nodes, includeExtension: includeExtension) }
        self.onCopyViaSSH = { nodes in onCopyViaSSH(nodes.map(\.url)) }
        onCompress = { nodes in viewModel.compressSelection(nodes) }
        onExtract = { nodes in viewModel.extractSelection(nodes) }
        canExtract = { nodes in viewModel.canExtract(nodes) }
        quickActionOptions = { nodes in viewModel.quickActionOptions(for: nodes) }
        onQuickAction = { action, nodes in viewModel.promptQuickAction(action, for: nodes) }
        tagSuggestions = {
            TagService.suggestions(
                standard: Array(NSWorkspace.shared.fileLabels.dropFirst()),
                inFolder: viewModel.tagsInFolder,
                excluding: []
            )
        }
        onSetTag = { tag, adding, nodes in
            Task {
                if let message = await viewModel.setTag(tag, adding: adding, on: nodes) {
                    viewModel.reportError(message)
                }
            }
        }
        onRestore = { nodes in viewModel.restore(nodes) }
        onDeletePermanently = { nodes in viewModel.deletePermanently(nodes) }
        isViewingTrash = viewModel.currentDirectory == Self.trashURL
        canPaste = { viewModel.canPaste }
        onDrop = { urls, targetNode, move in
            viewModel.handleDrop(urls: urls, into: targetNode?.url ?? viewModel.currentDirectory, move: move)
        }
        onMakeAliases = { urls, targetNode in
            viewModel.makeAliases(urls, in: targetNode?.url ?? viewModel.currentDirectory)
        }
    }

    private static let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
}

/// Gates opening "Copy via SSH" itself behind Touch ID/password, not
/// just the eventual `scp` call inside it — the dialog's saved
/// destinations list surfaces which servers/credentials are configured
/// (and prefills a stored password) as soon as it's opened, so the
/// check needs to happen before that, not after. `present` opens the
/// dialog for those URLs.
@MainActor
func requestSSHCopy(for urls: [URL], present: @escaping ([URL]) -> Void) {
    guard SSHDeviceAuthenticationPreferenceService().isEnabled() else {
        present(urls)
        return
    }
    Task {
        let reason = urls.count == 1 ? "copy \"\(urls[0].lastPathComponent)\" via SSH" : "copy \(urls.count) items via SSH"
        if await DeviceAuthenticationService().authenticate(reason: reason) {
            present(urls)
        }
    }
}
