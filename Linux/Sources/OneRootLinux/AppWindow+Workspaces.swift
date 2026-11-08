import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Workspaces in the window: New Workspace, the sidebar's right-click menu
/// (open, edit, delete, unpin), and Add to Workspace on a folder.
extension AppWindow {
    func addWorkspaceActions() {
        window.addAction(SimpleAction(name: "new-workspace") { [weak self] in self?.newWorkspace() })
        app.application.setAccelerators(["<Control><Alt>n"], for: "win.new-workspace")
        window.addAction(SimpleAction(name: "sidebar-open") { [weak self] in self?.activateSidebarEntry(inNewTab: false) })
        window.addAction(SimpleAction(name: "sidebar-open-tab") { [weak self] in self?.activateSidebarEntry(inNewTab: true) })
        window.addAction(SimpleAction(name: "sidebar-unpin") { [weak self] in
            if case .destination(let destination)? = self?.sidebarMenuEntry { PinnedLocationsStore.shared.unpin(destination.url) }
        })
        func sidebarURL() -> URL? {
            if case .destination(let destination)? = self.sidebarMenuEntry { return destination.url }
            return nil
        }
        window.addAction(SimpleAction(name: "sidebar-eject") { [weak self] in
            if case .destination(let destination)? = self?.sidebarMenuEntry { self?.destinations.eject(destination) }
        })
        window.addAction(SimpleAction(name: "sidebar-copy-path") { [weak self] in
            guard let self, let url = sidebarURL() else { return }
            self.activePane?.copyPaths([url])
            self.showToast("Copied the path")
        })
        window.addAction(SimpleAction(name: "sidebar-show-in-file-manager") { [weak self] in
            if let url = sidebarURL() { self?.showInFileManager([url]) }
        })
        window.addAction(SimpleAction(name: "sidebar-terminal") { [weak self] in
            if let url = sidebarURL() { self?.openTerminal(at: url) }
        })
        window.addAction(SimpleAction(name: "empty-trash") { [weak self] in self?.confirmEmptyTrash() })
        window.addAction(SimpleAction(name: "workspace-edit") { [weak self] in
            guard let self, case .workspace(let workspace)? = self.sidebarMenuEntry else { return }
            WorkspaceEditor.present(workspace, isNew: false, parent: self.window)
        })
        window.addAction(SimpleAction(name: "workspace-delete") { [weak self] in
            guard let self, case .workspace(let workspace)? = self.sidebarMenuEntry else { return }
            WorkspaceEditor.confirmDelete(workspace, parent: self.window)
        })
        window.addAction(SimpleAction(name: "add-to-workspace", parameterType: "s") { [weak self] parameter in
            guard let self, let target = parameter.stringValue else { return }
            self.addSelectionToWorkspace(target)
        })
    }

    func newWorkspace() {
        let store = WorkspaceStore.shared
        var workspace = Workspace(name: store.uniqueName())
        if let folder = activePane?.currentDirectory { workspace.folders = [folder] }
        WorkspaceEditor.present(workspace, isNew: true, parent: window) { [weak self] saved in
            self?.showToast("Created Workspace \u{201C}\(saved.name)\u{201D}")
        }
    }

    private func activateSidebarEntry(inNewTab: Bool) {
        switch sidebarMenuEntry {
        case .destination(let destination)?: viewModel.selectDestination(destination, inNewTab: inNewTab)
        case .workspace(let workspace)?: viewModel.openWorkspace(workspace, inNewTab: inNewTab)
        case nil: break
        }
    }

    func showSidebarMenu(_ entry: Sidebar.Entry, row: Widget, x: Double, y: Double) {
        sidebarMenuEntry = entry
        let menu = GMenuRef()
        let open = GMenuRef()
        open.append("Open", action: "win.sidebar-open")
        open.append("Open in New Tab", action: "win.sidebar-open-tab")
        menu.appendSection(nil, section: open)
        switch entry {
        case .workspace:
            let manage = GMenuRef()
            manage.append("Edit Workspace\u{2026}", action: "win.workspace-edit")
            manage.append("Delete Workspace\u{2026}", action: "win.workspace-delete")
            menu.appendSection(nil, section: manage)
        case .destination(let destination):
            if PinnedLocationsStore.shared.isPinned(destination.url) {
                let pin = GMenuRef()
                pin.append("Remove from Sidebar", action: "win.sidebar-unpin")
                menu.appendSection(nil, section: pin)
            }
            if destination.isEjectable {
                let eject = GMenuRef()
                eject.append(destination.kind == .networkVolume ? "Disconnect" : "Eject", action: "win.sidebar-eject")
                menu.appendSection(nil, section: eject)
            }
            if destination.kind == .trash {
                let trash = GMenuRef()
                trash.append("Empty Trash\u{2026}", action: "win.empty-trash")
                menu.appendSection(nil, section: trash)
            }
            if !destination.kind.isVirtual {
                let folder = GMenuRef()
                folder.append("Copy Path", action: "win.sidebar-copy-path")
                folder.append("Show in File Manager", action: "win.sidebar-show-in-file-manager")
                if destination.kind != .trash { folder.append("Open in Terminal", action: "win.sidebar-terminal") }
                menu.appendSection(nil, section: folder)
            }
        }
        sidebar.showMenu(menu, in: row, x: x, y: y)
    }

    /// "Add to Workspace": each Workspace that doesn't already cover `folder`
    /// (checked-and-disabled by name when it does), then a new one.
    func addToWorkspaceMenu(for folder: URL) -> GMenuRef {
        let menu = GMenuRef()
        let existing = GMenuRef()
        for workspace in WorkspaceStore.shared.workspaces {
            let covered = workspace.contains(folder)
            let item = GMenuItemRef(label: covered ? "\(workspace.name) \u{2713}" : workspace.name, action: covered ? "win.no-action" : "win.add-to-workspace")
            if !covered { item.setTargetValue(Variant.string(workspace.id.uuidString)) }
            existing.appendItem(item)
        }
        menu.appendSection(nil, section: existing)
        let new = GMenuRef()
        let item = GMenuItemRef(label: "New Workspace with \u{201C}\(folder.lastPathComponent)\u{201D}", action: "win.add-to-workspace")
        item.setTargetValue(Variant.string("new"))
        new.appendItem(item)
        menu.appendSection(nil, section: new)
        return menu
    }

    private func addSelectionToWorkspace(_ target: String) {
        let folder = selection.count == 1 && selection[0].isDirectory ? selection[0].url : activePane?.currentDirectory
        guard let folder else { return }
        let store = WorkspaceStore.shared
        if target == "new" {
            let workspace = store.create(with: folder)
            showToast("Created Workspace \u{201C}\(workspace.name)\u{201D}")
        } else if let id = UUID(uuidString: target), let workspace = store.workspace(id) {
            store.addFolders([folder], to: id)
            showToast("Added \u{201C}\(folder.lastPathComponent)\u{201D} to \u{201C}\(workspace.name)\u{201D}")
        }
    }
}

extension AppWindow {
    /// Empty Trash: asks first, then deletes what is in the Trash for good
    /// (a File Operations entry records it, as on the Mac).
    func confirmEmptyTrash() {
        guard let trash = destinations.allDestinations.first(where: { $0.kind == .trash }) else {
            showToast("There is no Trash to empty here.")
            return
        }
        let dialog = Dialogs.alert(
            heading: "Empty the Trash?",
            body: "This will permanently erase the items in the Trash. This can\u{2019}t be undone.",
            responses: [("cancel", "Cancel"), ("empty", "Empty Trash")], destructive: "empty")
        dialog.onResponse { [weak self] response in
            guard response == "empty", let self else { return }
            let node = FileNode(url: trash.url, name: trash.name, isDirectory: true, size: nil, modificationDate: nil, kind: nil)
            self.hierarchyModel.emptyTrash(node)
        }
        dialog.present(window)
    }
}
