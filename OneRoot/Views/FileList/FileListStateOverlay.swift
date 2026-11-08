import AppKit
import SwiftUI

/// What the file list says when it has no rows to show: still loading,
/// couldn't be read (with a way to fix a permissions problem), nothing
/// matches the filter, or the folder is simply empty. Drawn over the
/// AppKit list; only the buttons take clicks, so right-clicking the empty
/// space still gets the background menu (New Folder, Paste).
struct FileListStateOverlay: View {
    var viewModel: FileListViewModel

    /// A listing that comes back quickly shouldn't flash a spinner.
    @State private var showsSlowLoading = false

    var body: some View {
        Group {
            if !viewModel.items.isEmpty {
                EmptyView()
            } else if viewModel.isLoading {
                if showsSlowLoading {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        message("Loading…")
                    }
                }
            } else if viewModel.isPermissionDenied {
                VStack(spacing: 10) {
                    symbol("lock")
                    message("OneRoot doesn't have permission to open this folder.")
                    Button("Open Privacy & Security Settings…", action: openFullDiskAccessSettings)
                        .help("Grant OneRoot Full Disk Access")
                }
            } else if let errorMessage = viewModel.listingErrorMessage {
                VStack(spacing: 10) {
                    symbol("exclamationmark.circle")
                    message("This folder can't be opened.")
                    message(errorMessage, secondary: true)
                }
            } else if viewModel.filter.hasFilters {
                VStack(spacing: 10) {
                    if let filterError = viewModel.filterError {
                        message(filterError)
                    } else {
                        message(viewModel.filter.pattern.isEmpty || viewModel.filter.hasFiltersBesidesName
                            ? "No items match the filters."
                            : "No items match “\(viewModel.filter.pattern)”.")
                    }
                    Button("Clear Filters") { viewModel.clearFilter() }
                }
            } else if let location = viewModel.virtualLocation {
                message(location.emptyMessage)
            } else if viewModel.currentDirectory != nil {
                message("This folder is empty.")
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .task(id: viewModel.isLoading) {
            showsSlowLoading = false
            guard viewModel.isLoading else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { showsSlowLoading = true }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private func message(_ text: String, secondary: Bool = false) -> some View {
        Text(text)
            .font(secondary ? .callout : .body)
            .foregroundStyle(secondary ? .tertiary : .secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
