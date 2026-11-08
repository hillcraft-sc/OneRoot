import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Creates or edits a Workspace: its name and its folders (added with a
/// folder chooser, removed, moved up or down). Each folder stays where it is.
/// The GTK counterpart of the Mac's WorkspaceEditorView, over the shared
/// `Workspace` and `WorkspaceStore`.
@MainActor
enum WorkspaceEditor {
    static func present(_ workspace: Workspace, isNew: Bool, parent: Widget?,
                        store: WorkspaceStore = .shared, onSave: ((Workspace) -> Void)? = nil) {
        var draft = workspace
        let dialog = Dialogs.alert(
            heading: isNew ? "New Workspace" : "Edit Workspace",
            body: "Each folder stays where it is \u{2014} the Workspace only shows them together.",
            responses: [("cancel", "Cancel"), ("save", isNew ? "Create" : "Save")], suggested: "save")
        dialog.preferWideLayout = true

        let name = Entry()
        name.text = draft.name
        name.placeholderText = "Name"
        name.activatesDefault = true
        name.setAccessibleLabel("Workspace name")

        // The icon: one of the Mac's ten, shown as its closest Linux icon.
        let icons = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        icons.addCSSClass(.linked)
        icons.setAccessibleLabel("Icon")
        var firstIcon: ToggleButton?
        for symbol in Workspace.symbolChoices {
            let button = ToggleButton()
            button.child = Image(iconName: WorkspaceIcons.iconName(for: symbol))
            button.tooltipText = WorkspaceIcons.title(for: symbol)
            button.setAccessibleLabel("Icon: \(WorkspaceIcons.title(for: symbol))")
            if let firstIcon { button.setGroup(firstIcon) } else { firstIcon = button }
            button.active = draft.symbolName == symbol
            button.onToggled { if button.active { draft.symbolName = symbol } }
            icons.append(button)
        }

        let list = ListBox()
        list.addCSSClass("boxed-list")
        list.selectionMode = GTK_SELECTION_NONE
        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.pointer), 240)

        let add = Button(label: "Add Folder\u{2026}")
        add.halign = GTK_ALIGN_START
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        content.append(icons)
        content.append(name)
        content.append(scroller)
        content.append(add)
        dialog.extraChild = content

        func rebuild() {
            list.removeAll()
            if draft.folders.isEmpty {
                let empty = Label("No folders yet")
                empty.addCSSClass(.dimLabel)
                empty.marginTop = 10
                empty.marginBottom = 10
                list.append(empty)
            }
            for (index, folder) in draft.folders.enumerated() {
                let row = ActionRow(title: folder.lastPathComponent, subtitle: folder.deletingLastPathComponent().path)
                let up = Button(iconName: "go-up-symbolic")
                let down = Button(iconName: "go-down-symbolic")
                let remove = Button(iconName: "list-remove-symbolic")
                for (button, label) in [(up, "Move \(folder.lastPathComponent) up"), (down, "Move \(folder.lastPathComponent) down"),
                                        (remove, "Remove \(folder.lastPathComponent)")] {
                    button.addCSSClass(.flat)
                    button.valign = GTK_ALIGN_CENTER
                    button.setAccessibleLabel(label)
                    button.tooltipText = label
                }
                remove.tooltipText = "Remove from the Workspace (the folder isn\u{2019}t touched)"
                up.sensitive = index > 0
                down.sensitive = index < draft.folders.count - 1
                up.onClicked { draft.folders.swapAt(index, index - 1); rebuild() }
                down.onClicked { draft.folders.swapAt(index, index + 1); rebuild() }
                remove.onClicked { draft.folders.remove(at: index); rebuild() }
                row.addSuffix(up)
                row.addSuffix(down)
                row.addSuffix(remove)
                list.append(row)
            }
        }
        rebuild()

        add.onClicked {
            let chooser = FileDialog()
            chooser.title = "Add Folder to \u{201C}\(draft.name)\u{201D}"
            chooser.acceptLabel = "Add"
            chooser.modal = true
            chooser.selectFolder(parent: parent) { result in
                guard case .success(let path?) = result else { return }
                draft = draft.addingFolders([URL(fileURLWithPath: path, isDirectory: true)])
                rebuild()
            }
        }
        name.onChanged { draft.name = name.text }

        dialog.onResponse { response in
            guard response == "save" else { return }
            draft.name = name.text
            store.save(draft)
            onSave?(draft)
        }
        dialog.present(parent)
        MainContext.delay(ms: 60) { _ = name.grabFocus() }
    }

    /// Asks before deleting; the folders themselves are never touched.
    static func confirmDelete(_ workspace: Workspace, parent: Widget?, store: WorkspaceStore = .shared) {
        let dialog = Dialogs.alert(
            heading: "Delete \u{201C}\(workspace.name)\u{201D}?",
            body: "Its folders stay where they are; only the Workspace is removed.",
            responses: [("cancel", "Cancel"), ("delete", "Delete Workspace")], destructive: "delete")
        dialog.onResponse { response in
            if response == "delete" { store.delete(workspace.id) }
        }
        dialog.present(parent)
    }
}
