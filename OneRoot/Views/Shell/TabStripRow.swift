import SwiftUI

/// The top of the window, where a title bar would be: the tabs, then the
/// folder filter, Advanced Search, and the toggles for each pane. Empty
/// space here drags the window (see `TrailingTabDropView`).
struct TabStripRow: View {
    var tab: Tab
    var layout: WindowLayoutModel
    let windowViewModel: WindowViewModel

    var body: some View {
        HStack(spacing: 6) {
            // Sits on the bottom edge of the band, touching the card below.
            TabBarView(windowViewModel: windowViewModel)
                .frame(maxHeight: .infinity, alignment: .bottom)
            // Advanced Search is the last item of the field's filter menu
            // (and ⌥⌘/, View ▸ Advanced Search) — not a button of its own.
            SearchFieldView(viewModel: tab.fileListViewModel)

            Divider().frame(height: 16)

            paneToggle("Destinations", "sidebar.left", \.showsDestinations, shortcut: "⌃⌘S")
            paneToggle("Folder Hierarchy", "list.bullet.indent", \.showsHierarchy, shortcut: "⌃⌘H")
            paneToggle("Inspector", "sidebar.right", \.showsInspector, shortcut: "⌥⌘I")
            Button {
                windowViewModel.setWorkspaceExpanded(!layout.layout.isWorkspaceExpanded)
            } label: {
                Image(systemName: "rectangle.bottomthird.inset.filled")
            }
            .buttonStyle(BarButtonStyle(isOn: layout.layout.isWorkspaceExpanded))
            .help("\(layout.layout.isWorkspaceExpanded ? "Hide" : "Show") Tools (⌃⌘B)")
            .accessibilityLabel("Tools")
            .accessibilityValue(layout.layout.isWorkspaceExpanded ? "Shown" : "Hidden")
        }
        .padding(.trailing, 10)
    }

    private func paneToggle(_ title: String, _ systemImage: String, _ keyPath: WritableKeyPath<WindowLayout, Bool>, shortcut: String) -> some View {
        let isOn = layout.layout[keyPath: keyPath]
        return Button {
            layout.toggle(keyPath)
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(BarButtonStyle(isOn: isOn))
        .help("\(isOn ? "Hide" : "Show") \(title) (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
    }
}
