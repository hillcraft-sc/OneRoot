import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The fields of an SSH destination — host, port, user, remote folder, key,
/// password — as one boxed list of rows, shared by Copy via SSH and the
/// editor in Settings ▸ SSH. Holds text only; `SSHDestinationDraft` checks it.
@MainActor
final class SSHDestinationForm {
    let widget = ListBox()
    var onChange: (() -> Void)?

    private let host = EntryRow()
    private let port = EntryRow()
    private let user = EntryRow()
    private let path = EntryRow()
    private let key = EntryRow()
    private let password = PasswordEntryRow()
    private let remember = SwitchRow()
    private let parent: () -> Widget?

    init(parent: @escaping () -> Widget?) {
        self.parent = parent
        widget.addCSSClass("boxed-list")
        widget.selectionMode = GTK_SELECTION_NONE
        for (row, title) in [(host, "Host"), (port, "Port"), (user, "User name"), (path, "Remote folder"),
                             (key, "Private key (optional)"), (password, "Password or key passphrase")] {
            row.title = title
            row.setAccessibleLabel(title)
            row.onChanged { [weak self] in self?.onChange?() }
            widget.append(row)
        }
        host.inputPurpose = GTK_INPUT_PURPOSE_URL
        port.inputPurpose = GTK_INPUT_PURPOSE_DIGITS
        let browse = Button(iconName: "document-open-symbolic")
        browse.addCSSClass(.flat)
        browse.valign = GTK_ALIGN_CENTER
        browse.tooltipText = "Choose a Private Key File"
        browse.setAccessibleLabel("Choose a private key file")
        browse.onClicked { [weak self] in self?.chooseKey() }
        key.addSuffix(browse)
        remember.title = "Remember the password in the keyring"
        remember.subtitle = "Kept in the desktop keyring (Secret Service), never in OneRoot\u{2019}s settings."
        remember.onNotify(.custom("active")) { [weak self] in self?.onChange?() }
        widget.append(remember)
    }

    var draft: SSHDestinationDraft {
        get {
            var draft = SSHDestinationDraft()
            draft.host = host.text; draft.port = port.text; draft.username = user.text
            draft.remotePath = path.text; draft.privateKeyPath = key.text
            draft.password = password.text; draft.remembersPassword = remember.active
            return draft
        }
        set {
            host.text = newValue.host; port.text = newValue.port; user.text = newValue.username
            path.text = newValue.remotePath; key.text = newValue.privateKeyPath
            password.text = newValue.password; remember.active = newValue.remembersPassword
        }
    }

    func focusFirst() { _ = host.grabFocus() }

    /// Disables every field (while a copy runs).
    var isEditable: Bool = true {
        didSet { widget.sensitive = isEditable }
    }

    private func chooseKey() {
        let dialog = FileDialog()
        dialog.title = "Private Key"
        dialog.acceptLabel = "Choose"
        dialog.modal = true
        dialog.open(parent: parent()) { [weak self] result in
            guard case .success(let chosen?) = result else { return }
            self?.key.text = chosen
        }
    }
}
