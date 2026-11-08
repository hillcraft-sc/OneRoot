import SwiftUI

/// Creates or edits a Workspace: its name, icon, and folders — added with
/// OneRoot's folder chooser, removed, or dragged into order. Each folder
/// shows where it really is.
struct WorkspaceEditorView: View {
    @Environment(\.appTheme) private var theme
    @State var workspace: Workspace
    let isNew: Bool
    var onSave: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFolder = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Workspace" : "Edit Workspace")
                .font(.headline)

            HStack(spacing: 8) {
                Menu {
                    ForEach(Workspace.symbolChoices, id: \.self) { symbol in
                        Button {
                            workspace.symbolName = symbol
                        } label: {
                            Label(symbol, systemImage: symbol).labelStyle(.iconOnly)
                        }
                    }
                } label: {
                    Image(systemName: workspace.symbolName)
                }
                .fixedSize()
                .help("Icon")
                .accessibilityLabel("Icon")
                TextField("Name", text: $workspace.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folders")
                    .font(.subheadline.weight(.semibold))
                Text("Each stays where it is — the Workspace only shows them together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List {
                    ForEach(workspace.folders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(theme.icons.folder.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.lastPathComponent)
                                Text(FileOperationText.shortPath(folder))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                workspace.folders.removeAll { $0 == folder }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from the Workspace (the folder isn't touched)")
                            .accessibilityLabel("Remove \(folder.lastPathComponent)")
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { workspace.folders.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 160)
                .overlay {
                    if workspace.folders.isEmpty {
                        Text("No folders yet")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                HelpButton(topic: .workspaces)
                Button("Add Folder\u{2026}") { isChoosingFolder = true }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    onSave(workspace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
        .onAppear { if isNew { isNameFocused = true } }
        .sheet(isPresented: $isChoosingFolder) {
            FileChooserView(
                multipleFoldersStartingAt: workspace.folders.last?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser,
                message: "Choose folders to add to \u{201C}\(workspace.name)\u{201D}. \u{2318}-click to pick more than one.",
                chooseButtonTitle: "Add"
            ) { urls in
                workspace = workspace.addingFolders(urls)
            }
        }
    }
}
