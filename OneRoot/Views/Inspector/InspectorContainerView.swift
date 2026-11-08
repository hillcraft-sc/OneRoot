import SwiftUI

/// The right-hand Inspector card: context for whatever's selected in the
/// focused pane (`InspectorView`).
///
/// Reads the selection straight from the focused pane's
/// `FileListViewModel.selectedNodes` — the typed boundary the AppKit file
/// views already report into — never from the table itself.
struct InspectorContainerView: View {
    @Bindable var tab: Tab
    /// False while collapsed: the pane stays alive in the split view, but
    /// shouldn't keep loading previews nobody can see.
    let isVisible: Bool

    var body: some View {
        if isVisible {
            InspectorContent(viewModel: tab.fileListViewModel, section: $tab.inspectorSection)
        } else {
            Color.clear
        }
    }
}

private struct InspectorContent: View {
    var viewModel: FileListViewModel
    @Binding var section: InspectorSection

    var body: some View {
        InspectorView(viewModel: viewModel, section: $section)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Inspector")
    }
}
