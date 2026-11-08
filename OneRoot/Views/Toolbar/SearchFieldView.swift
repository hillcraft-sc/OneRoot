import AppKit
import SwiftUI

/// Filters the current folder's list by name (SPEC.md §4.4), with the
/// filter button beside it for the rest — Kind, Date Modified, Size, … —
/// which then show as chips under the Context Bar (`FolderFilterBar`).
/// Non-recursive: only the folder shown is filtered; Search Subfolders
/// takes the same filter into Advanced Search.
struct SearchFieldView: View {
    @Bindable var viewModel: FileListViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.openWindow) private var openWindow
    /// The filter chosen from the menu, edited in a popover here.
    @State private var editing: SearchChip.Field?

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.fieldColor))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.separatorColor))
            .frame(width: 180)

            AddFilterMenu(
                context: .folder,
                appearance: .icon(filled: viewModel.filter.hasFiltersBesidesName),
                onCustom: { field in DispatchQueue.main.async { editing = field } },
                onAdvancedSearch: { openWindow(id: OneRootApp.advancedSearchWindowID) }
            )
            // Not rebuilt (and so closed) when the field loses focus as the
            // menu opens — see `AddFilterMenu`.
            .equatable()
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filter this folder by kind, date, size, extension, or tag — or open Advanced Search (⌥⌘/)")
            .popover(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
                if let editing {
                    FilterChipEditor(
                        criteria: $viewModel.filter,
                        field: editing,
                        context: .folder,
                        tagSuggestions: FolderFilterBar.tagSuggestions(for: viewModel)
                    )
                        .padding(14)
                }
            }
        }
        .onChange(of: viewModel.searchFieldFocusTrigger) { _, _ in
            isFocused = true
        }
    }
}
