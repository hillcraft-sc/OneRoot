import SwiftUI

/// "Add to Workspace ▸": each Workspace — checked and unavailable if it
/// already covers `folder` (it's one of its folders or inside one) — then
/// a new one holding `folder`. Shared by the Context Bar's More
/// menu and the Inspector.
struct AddToWorkspaceMenu: View {
    let folder: URL
    private var store = WorkspaceStore.shared

    var body: some View {
        Menu("Add to Workspace") {
            ForEach(store.workspaces) { workspace in
                let isIn = workspace.contains(folder)
                Button {
                    store.addFolders([folder], to: workspace.id)
                } label: {
                    if isIn { Label(workspace.name, systemImage: "checkmark") } else { Text(workspace.name) }
                }
                .disabled(isIn)
            }
            if !store.workspaces.isEmpty { Divider() }
            Button("New Workspace with \u{201C}\(folder.lastPathComponent)\u{201D}") {
                store.create(with: folder)
            }
        }
    }
}
