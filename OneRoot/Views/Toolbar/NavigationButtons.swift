import SwiftUI

/// Back / Forward / Up / Refresh — the start of the location bar.
struct NavigationButtons: View {
    var viewModel: FileListViewModel
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .help("Back (⌘[)")
            .accessibilityLabel("Back")

            Button {
                viewModel.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .help("Forward (⌘])")
            .accessibilityLabel("Forward")

            Button {
                viewModel.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!viewModel.canGoUp)
            .help("Up One Level (⌘↑)")
            .accessibilityLabel("Up One Level")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
        }
        .buttonStyle(BarButtonStyle())
        .fontWeight(.medium)
    }
}
