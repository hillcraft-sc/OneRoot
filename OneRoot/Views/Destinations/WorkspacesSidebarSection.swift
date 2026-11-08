import SwiftUI

/// The sidebar's Workspaces section: each Workspace, and **+** for a new
/// one. Choosing one shows its folders in the hierarchy and takes the tab
/// to the first. Dropping folders on one adds them to it — as references;
/// nothing is moved.
struct WorkspacesSidebarSection: View {
    var store: WorkspaceStore
    var activeTab: Tab
    var onOpen: (Workspace, _ inNewTab: Bool) -> Void

    /// The Workspace being created or edited in the sheet.
    @State private var editing: WorkspaceEditing?
    @State private var deleting: Workspace?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Workspaces")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    editing = WorkspaceEditing(workspace: Workspace(name: store.uniqueName()), isNew: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("New Workspace")
                .accessibilityLabel("New Workspace")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)

            if store.workspaces.isEmpty {
                Button {
                    editing = WorkspaceEditing(workspace: Workspace(name: store.uniqueName()), isNew: true)
                } label: {
                    Label("New Workspace", systemImage: "plus.square.dashed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                }
                .buttonStyle(.plain)
                .help("Group folders from different places for one project")
            }
            ForEach(store.workspaces) { workspace in
                WorkspaceRow(
                    workspace: workspace,
                    isSelected: activeTab.workspaceID == workspace.id,
                    onChoose: { onOpen(workspace, false) },
                    onDropFolders: { store.addFolders($0, to: workspace.id) }
                )
                .contextMenu {
                    Button("Open in New Tab") { onOpen(workspace, true) }
                    Divider()
                    Button("Edit Workspace\u{2026}") { editing = WorkspaceEditing(workspace: workspace, isNew: false) }
                    Button("Delete Workspace\u{2026}") { deleting = workspace }
                }
            }
        }
        .sheet(item: $editing) { editing in
            WorkspaceEditorView(workspace: editing.workspace, isNew: editing.isNew) { saved in
                store.save(saved)
                if editing.isNew, !saved.folders.isEmpty { onOpen(saved, false) }
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { workspace in
            Button("Delete Workspace", role: .destructive) { store.delete(workspace.id) }
        } message: { _ in
            Text("Only the Workspace is removed. Its folders and files stay where they are.")
        }
    }
}

struct WorkspaceEditing: Identifiable {
    var workspace: Workspace
    let isNew: Bool
    var id: UUID { workspace.id }
}

/// One Workspace: its icon and name, styled like the destination rows.
private struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    var onChoose: () -> Void
    var onDropFolders: ([URL]) -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: workspace.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? theme.accentColor : Color.primary.opacity(0.7))
                .frame(width: 20)
            Text(workspace.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text("\(workspace.folders.count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(theme.isDark ? 0.12 : 0.08) : (isHovering ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.accentColor, lineWidth: isDropTarget ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onChoose)
        .onHover { isHovering = $0 }
        .help(workspace.folders.isEmpty ? "No folders yet — drop folders here, or Edit Workspace" : workspace.folders.map(\.path).joined(separator: "\n"))
        .onDrop(of: [.fileURL], delegate: DestinationDropDelegate(isTargeted: $isDropTarget) { urls, _ in
            // Only folders are added; a Workspace refers to them, so
            // nothing is moved or copied.
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            if !folders.isEmpty { onDropFolders(folders) }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspace.name), workspace, \(workspace.folders.count == 1 ? "1 folder" : "\(workspace.folders.count) folders")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onChoose() }
    }
}
