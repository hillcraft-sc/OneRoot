import AppKit
import SwiftUI

/// The current folder's filter chips, under the Context Bar while anything
/// filters the list, with Search Subfolders (the same filter as an
/// Advanced Search of this folder and everything in it) and Clear — the
/// only way a filter goes away: it stays on from folder to folder.
struct FolderFilterBar: View {
    @Bindable var viewModel: FileListViewModel
    /// In a Workspace: Search Workspace searches all its folders at once.
    var workspace: Workspace?
    private var handoff = SearchHandoffCenter.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        FilterChipBar(
            criteria: $viewModel.filter,
            context: .folder,
            nameError: viewModel.filterError,
            tagSuggestions: Self.tagSuggestions(for: viewModel)
        ) {
            Text(viewModel.items.count == 1 ? "1 match" : "\(viewModel.items.count) matches")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let workspace, workspace.folders.count > 1 {
                Button {
                    hand(viewModel.filterAsWorkspaceSearch(workspace))
                } label: {
                    Label("Search Workspace", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Search all \(workspace.folders.count) folders of \u{201C}\(workspace.name)\u{201D} with these filters, in Advanced Search")
            }
            Button {
                hand(viewModel.filterAsSubfolderSearch())
            } label: {
                Label("Search Subfolders", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.currentDirectory == nil)
            .help("Search this folder and everything inside it with these filters, in Advanced Search")
            Button {
                viewModel.clearFilter()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove every filter")
        }
    }

    private func hand(_ criteria: SearchCriteria?) {
        guard let criteria else { return }
        handoff.hand(criteria)
        openWindow(id: OneRootApp.advancedSearchWindowID)
    }

    /// The standard color tags, then the others used in this folder.
    static func tagSuggestions(for viewModel: FileListViewModel) -> [String] {
        TagService.suggestions(
            standard: Array(NSWorkspace.shared.fileLabels.dropFirst()),
            inFolder: viewModel.tagsInFolder,
            excluding: viewModel.filter.tags
        )
    }
}
