import SwiftUI

/// The folder-hierarchy pane: the existing `NSOutlineView` tree, rooted at
/// the active tab's `HierarchyRoot`. Its conflict and error alerts live at
/// the window level instead (`hierarchyAlerts`), so a drop onto a
/// destination still gets its prompt while this pane is collapsed.
struct FolderHierarchyView: View {
    var viewModel: FolderHierarchyViewModel
    var onSelect: (FileNode) -> Void
    var onOpenInNewTab: (FileNode) -> Void

    /// Fed by `viewModel.revealRequest` (which the active tab's current
    /// directory drives). Local `@State`, not a binding up to
    /// `MainWindowView`, so a navigation reveals the tree without
    /// re-rendering that whole view.
    @State private var revealTarget: URL?
    @State private var renamingNode: FileNode?
    @State private var renameText = ""
    @State private var newFolderParent: FileNode?
    @State private var newFolderName = "New Folder"

    var body: some View {
        FolderOutlineRepresentable(
            viewModel: viewModel,
            onSelect: onSelect,
            onOpenInNewTab: onOpenInNewTab,
            revealRequest: $revealTarget,
            renamingNode: $renamingNode,
            renameText: $renameText,
            newFolderParent: $newFolderParent
        )
        .onChange(of: viewModel.revealRequest) { _, request in revealTarget = request?.url }
        .alert(
            "Rename",
            isPresented: Binding(
                get: { renamingNode != nil },
                set: { isPresented in if !isPresented { renamingNode = nil } }
            ),
            actions: {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let node = renamingNode {
                        viewModel.rename(node, to: renameText)
                    }
                    renamingNode = nil
                }
                Button("Cancel", role: .cancel) { renamingNode = nil }
            }
        )
        .alert(
            "New Folder",
            isPresented: Binding(
                get: { newFolderParent != nil },
                set: { isPresented in if !isPresented { newFolderParent = nil } }
            ),
            actions: {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    if let parent = newFolderParent {
                        viewModel.createFolder(in: parent, named: newFolderName)
                    }
                    newFolderParent = nil
                    newFolderName = "New Folder"
                }
                Button("Cancel", role: .cancel) {
                    newFolderParent = nil
                    newFolderName = "New Folder"
                }
            }
        )
    }
}

extension View {
    /// The hierarchy's Replace/Keep Both/Skip and error alerts — attached
    /// once per window, to a view that's always on screen.
    func hierarchyAlerts(_ viewModel: FolderHierarchyViewModel) -> some View {
        modifier(HierarchyAlerts(viewModel: viewModel))
    }
}

private struct HierarchyAlerts: ViewModifier {
    var viewModel: FolderHierarchyViewModel

    func body(content: Content) -> some View {
        content
            .fileConflictPrompt(viewModel.pendingConflicts) { answer, id in
                viewModel.answerConflicts(answer, to: id)
            }
            .nameFixPrompt(viewModel.pendingNameFix) { answer, id in
                viewModel.answerNameFix(answer, to: id)
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in if !isPresented { viewModel.errorMessage = nil } }
                ),
                actions: { Button("OK") { viewModel.errorMessage = nil } },
                message: { Text(viewModel.errorMessage ?? "") }
            )
    }
}

private struct FolderOutlineRepresentable: NSViewRepresentable {
    var viewModel: FolderHierarchyViewModel
    var onSelect: (FileNode) -> Void
    var onOpenInNewTab: (FileNode) -> Void
    @Binding var revealRequest: URL?
    @Binding var renamingNode: FileNode?
    @Binding var renameText: String
    @Binding var newFolderParent: FileNode?

    func makeCoordinator() -> FolderOutlineViewController {
        FolderOutlineViewController(
            roots: viewModel.roots,
            ejectableRootURLs: viewModel.ejectableRootURLs,
            childLoader: viewModel.children(of:)
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = context.coordinator.outlineView
        // See `FolderOutlineViewController.apply`: themes paint the sidebar
        // color behind the outline, so the scroll view mustn't cover it.
        scrollView.drawsBackground = ThemeStore.shared.current.surfaces == nil
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onEject = { viewModel.eject($0) }
        context.coordinator.onOpenInNewTab = onOpenInNewTab
        context.coordinator.onCopy = { viewModel.copyNode($0) }
        context.coordinator.onCut = { viewModel.cutNode($0) }
        context.coordinator.onPaste = { viewModel.paste(into: $0) }
        context.coordinator.onRename = { node in
            renamingNode = node
            renameText = node.name
        }
        context.coordinator.onMoveToTrash = { viewModel.moveToTrash($0) }
        context.coordinator.onNewFolder = { newFolderParent = $0 }
        context.coordinator.onTogglePin = { viewModel.togglePin($0) }
        context.coordinator.onCopyPath = { viewModel.copyPath($0) }
        context.coordinator.onCopyName = { viewModel.copyName($0, includeExtension: true) }
        context.coordinator.onEmptyTrash = { viewModel.emptyTrash($0) }
        context.coordinator.canPaste = { viewModel.canPaste }
        context.coordinator.isPinned = { viewModel.isPinned($0.url) }
        context.coordinator.onDrop = { urls, targetNode, move in viewModel.handleDrop(urls: urls, into: targetNode, move: move) }
        context.coordinator.onMakeAliases = { urls, targetNode in viewModel.makeAliases(urls, in: targetNode.url) }

        context.coordinator.updateRoots(viewModel.roots, ejectableRootURLs: viewModel.ejectableRootURLs)
        context.coordinator.handleCollapseAllRequest(count: viewModel.collapseAllRequestCount)
        context.coordinator.handleExpandTopLevelRequest(count: viewModel.expandTopLevelRequestCount)
        context.coordinator.handleRefreshAllRequest(count: viewModel.refreshAllRequestCount)

        if let url = revealRequest {
            context.coordinator.reveal(url: url)
            DispatchQueue.main.async {
                revealRequest = nil
            }
        }
        if !viewModel.refreshRequests.isEmpty {
            let requests = viewModel.refreshRequests
            for url in requests {
                context.coordinator.refreshChildren(of: url)
            }
            DispatchQueue.main.async {
                viewModel.refreshRequests.subtract(requests)
            }
        }
    }
}
