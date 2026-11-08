import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Settings ▸ SSH: the saved destinations of Copy via SSH — add, edit,
/// remove — over the shared `SavedSSHDestinationsService`; passwords live
/// in the desktop keyring. The Mac's Touch ID gate has no Linux counterpart.
@MainActor
final class SSHSettingsPage {
    let page = PreferencesPage()
    private let store = SavedSSHDestinationsService()
    private let group = PreferencesGroup()
    private var rows: [Widget] = []
    private let parent: () -> Widget?

    init(parent: @escaping () -> Widget?) {
        self.parent = parent
        page.title = "SSH"
        page.name = "ssh"
        page.iconName = "network-server-symbolic"
        group.title = "Destinations"
        group.description = "Servers you copy files to with Copy via SSH (right-click \u{25B8} More). OneRoot never stores a password in its settings; a remembered one goes to the desktop keyring."
        let add = Button(label: "Add\u{2026}")
        add.valign = GTK_ALIGN_CENTER
        add.setAccessibleLabel("Add a destination")
        add.onClicked { [weak self] in self?.edit(nil) }
        group.headerSuffix = add
        page.add(group)
        rebuild()
    }

    private func rebuild() {
        for row in rows { group.remove(row) }
        rows = []
        let destinations = store.load()
        if destinations.isEmpty {
            let empty = ActionRow(title: "No destinations yet", subtitle: "Add one here, or save it from Copy via SSH.")
            group.add(empty)
            rows.append(empty)
        }
        for destination in destinations {
            let row = ActionRow(title: destination.name,
                                subtitle: "\(destination.username)@\(destination.host):\(destination.port) \u{2192} \(destination.remotePath)")
            let editButton = Button(iconName: "document-edit-symbolic")
            let removeButton = Button(iconName: "user-trash-symbolic")
            for (button, label) in [(editButton, "Edit \(destination.name)"), (removeButton, "Remove \(destination.name)")] {
                button.addCSSClass(.flat)
                button.valign = GTK_ALIGN_CENTER
                button.tooltipText = label
                button.setAccessibleLabel(label)
            }
            editButton.onClicked { [weak self] in self?.edit(destination) }
            removeButton.onClicked { [weak self] in
                KeyringService.ssh.remove(account: destination.id.uuidString)
                self?.store.remove(id: destination.id)
                self?.rebuild()
            }
            row.addSuffix(editButton)
            row.addSuffix(removeButton)
            group.add(row)
            rows.append(row)
        }
    }

    private func edit(_ existing: SavedSSHDestination?) {
        let dialog = Dialogs.alert(
            heading: existing == nil ? "Add SSH Destination" : "Edit SSH Destination",
            body: "Host, login and folder for Copy via SSH.",
            responses: [("cancel", "Cancel"), ("save", "Save")], suggested: "save")
        dialog.preferWideLayout = true
        let name = EntryRow()
        name.title = "Name (optional)"
        name.text = existing?.name ?? ""
        name.setAccessibleLabel("Destination name")
        let form = SSHDestinationForm(parent: parent)
        if let existing {
            form.draft = SSHDestinationDraft(existing, password: KeyringService.ssh.password(account: existing.id.uuidString) ?? "")
        } else {
            var draft = SSHDestinationDraft()
            draft.privateKeyPath = SSHCopyService.defaultPrivateKeyPath() ?? ""
            form.draft = draft
        }
        let nameBox = ListBox()
        nameBox.addCSSClass("boxed-list")
        nameBox.selectionMode = GTK_SELECTION_NONE
        nameBox.append(name)
        let install = Button(label: "Install Key on Server\u{2026}")
        install.halign = GTK_ALIGN_START
        install.tooltipText = "Logs in once with the password above and adds the key\u{2019}s public half to the server\u{2019}s authorized_keys. Safe to repeat."
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        content.append(nameBox)
        content.append(form.widget)
        content.append(install)
        dialog.extraChild = content

        install.onClicked { [parent] in
            let draft = form.draft
            guard let destination = draft.destination() else {
                Dialogs.showError("Check the Details", draft.problem ?? "", parent: parent())
                return
            }
            Task { @MainActor in
                do {
                    try await SSHCopyService().installKey(to: destination, password: draft.password.isEmpty ? nil : draft.password)
                    Dialogs.showError("Key Installed", "The key was added to \(destination.host).", parent: parent())
                } catch {
                    Dialogs.showError("Couldn\u{2019}t Install the Key", error.localizedDescription, parent: parent())
                }
            }
        }
        dialog.onResponse { [weak self] response in
            guard response == "save", let self else { return }
            let draft = form.draft
            guard let destination = draft.saved(id: existing?.id ?? UUID(), name: name.text) else {
                Dialogs.showError("Check the Details", draft.problem ?? "", parent: self.parent())
                return
            }
            self.store.upsert(destination)
            if draft.remembersPassword, !draft.password.isEmpty {
                do { try KeyringService.ssh.store(draft.password, account: destination.id.uuidString, label: "OneRoot SSH password") }
                catch { Dialogs.showError("Password Not Saved", error.localizedDescription, parent: self.parent()) }
            } else if !draft.remembersPassword {
                KeyringService.ssh.remove(account: destination.id.uuidString)
            }
            self.rebuild()
        }
        dialog.present(parent())
    }
}
