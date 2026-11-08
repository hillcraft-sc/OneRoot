import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Copy via SSH: prompts for a destination (or picks a saved one) and copies
/// the selected files there with `scp` (`SSHCopyService`, shared with the
/// Mac). Passwords go to the desktop keyring, never to OneRoot's settings.
@MainActor
enum SSHCopyDialog {
    static func present(files: [URL], window: AppWindow) {
        let store = SavedSSHDestinationsService()
        var saved = store.load()
        var selectedID: UUID?

        let title = files.count == 1 ? "Copy \u{201C}\(files[0].lastPathComponent)\u{201D} via SSH" : "Copy \(files.count) Items via SSH"
        let dialog = Dialogs.alert(
            heading: title,
            body: "Uses scp with your SSH keys and agent. A password is only needed when the server asks for one.",
            responses: [("cancel", "Cancel"), ("copy", "Copy")], suggested: "copy")
        dialog.preferWideLayout = true

        let form = SSHDestinationForm(parent: { window.window })
        var draft = SSHDestinationDraft()
        draft.privateKeyPath = SSHCopyService.defaultPrivateKeyPath() ?? ""
        form.draft = draft

        let list = ListBox()
        list.addCSSClass("boxed-list")
        list.selectionMode = GTK_SELECTION_SINGLE
        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.pointer), 120)
        let heading = Label("Saved destinations")
        heading.addCSSClass(.dimLabel)
        heading.halign = GTK_ALIGN_START
        let emptyNote = Label("Nothing saved yet")
        emptyNote.addCSSClass(.dimLabel)
        emptyNote.halign = GTK_ALIGN_START
        let saveButton = Button(label: "Save These Details")
        let removeButton = Button(label: "Remove Selected")
        removeButton.sensitive = false
        let buttons = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        buttons.append(saveButton)
        buttons.append(removeButton)
        let problem = Label("")
        problem.addCSSClass("error")
        problem.halign = GTK_ALIGN_START
        problem.wrap = true
        problem.visible = false

        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        content.append(heading)
        content.append(scroller)
        content.append(emptyNote)
        content.append(buttons)
        content.append(form.widget)
        content.append(problem)
        dialog.extraChild = content

        func rebuild() {
            list.removeAll()
            scroller.visible = !saved.isEmpty
            emptyNote.visible = saved.isEmpty
            for destination in saved {
                list.append(ActionRow(title: destination.name,
                                      subtitle: "\(destination.username)@\(destination.host):\(destination.port) \u{2192} \(destination.remotePath)"))
            }
        }
        rebuild()

        list.onRowSelected { row in
            guard let row, row.index < saved.count else {
                selectedID = nil
                removeButton.sensitive = false
                return
            }
            let destination = saved[row.index]
            selectedID = destination.id
            removeButton.sensitive = true
            form.draft = SSHDestinationDraft(destination, password: KeyringService.ssh.password(account: destination.id.uuidString) ?? "")
        }
        saveButton.onClicked {
            let current = form.draft
            guard let destination = current.saved(id: selectedID ?? UUID()) else {
                problem.text = current.problem ?? ""
                problem.visible = true
                return
            }
            problem.visible = false
            saved = store.upsert(destination)
            selectedID = destination.id
            storePassword(current, for: destination.id, problem: problem)
            rebuild()
        }
        removeButton.onClicked {
            guard let id = selectedID else { return }
            KeyringService.ssh.remove(account: id.uuidString)
            saved = store.remove(id: id)
            selectedID = nil
            removeButton.sensitive = false
            rebuild()
        }

        dialog.onResponse { response in
            guard response == "copy" else { return }
            let current = form.draft
            guard let destination = current.destination() else {
                // Keep the form: ask again with what was typed.
                Dialogs.showError("Check the Details", current.problem ?? "", parent: window.window)
                return
            }
            if current.remembersPassword, !current.password.isEmpty, let id = selectedID {
                storePassword(current, for: id, problem: nil)
            }
            run(files: files, destination: destination, password: current.password, window: window)
        }
        dialog.present(window.window)
        MainContext.delay(ms: 60) { form.focusFirst() }
    }

    private static func storePassword(_ draft: SSHDestinationDraft, for id: UUID, problem: Label?) {
        guard draft.remembersPassword, !draft.password.isEmpty else {
            if !draft.remembersPassword { KeyringService.ssh.remove(account: id.uuidString) }
            return
        }
        do {
            try KeyringService.ssh.store(draft.password, account: id.uuidString, label: "OneRoot SSH password")
        } catch {
            problem?.text = error.localizedDescription
            problem?.visible = true
        }
    }

    private static func run(files: [URL], destination: SSHDestination, password: String, window: AppWindow) {
        let what = files.count == 1 ? "\u{201C}\(files[0].lastPathComponent)\u{201D}" : "\(files.count) items"
        Task { @MainActor in
            // First contact with a server: show its fingerprint and only
            // trust it if asked, writing exactly that key to known_hosts.
            let hostKeys = SSHHostKeyService()
            if await !hostKeys.isKnown(host: destination.host, port: destination.port) {
                do {
                    let key = try await hostKeys.scan(host: destination.host, port: destination.port)
                    guard await confirm(hostKey: key, window: window) else { return }
                    try hostKeys.trust(key)
                } catch {
                    Dialogs.showError("Couldn\u{2019}t Check \(destination.host)", error.localizedDescription, parent: window.window)
                    return
                }
            }

            let progress = ProgressSheet(title: "Copying \(what) to \(destination.host)", window: window)
            let copy = Task { @MainActor in
                try await SSHCopyService().copy(files, to: destination, password: password.isEmpty ? nil : password) { update in
                    Task { @MainActor in progress.show(update) }
                }
            }
            progress.onCancel = { copy.cancel() }
            do {
                try await copy.value
                progress.close()
                window.showToast("Copied \(what) to \(destination.host)")
            } catch is CancellationError {
                progress.close()
                window.showToast("Stopped copying to \(destination.host)")
            } catch {
                progress.close()
                Dialogs.showError("Couldn\u{2019}t Copy to \(destination.host)", error.localizedDescription, parent: window.window)
            }
        }
    }

    /// Asks whether to trust a server's host key, showing its fingerprints.
    private static func confirm(hostKey: SSHHostKey, window: AppWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            let dialog = Dialogs.alert(
                heading: "Trust \(hostKey.host)?",
                body: "OneRoot hasn\u{2019}t connected to this server before, so it can\u{2019}t tell it is the real one. Compare this fingerprint with one you got from the server\u{2019}s owner. Trusting it saves the key to ~/.ssh/known_hosts.",
                responses: [("cancel", "Cancel"), ("trust", "Trust and Copy")], suggested: "trust", defaultResponse: "cancel")
            let fingerprints = Label(hostKey.fingerprints.joined(separator: "\n"))
            fingerprints.addCSSClass("monospace")
            fingerprints.selectable = true
            fingerprints.wrap = true
            fingerprints.xalign = 0
            fingerprints.setAccessibleLabel("Host key fingerprints")
            dialog.extraChild = fingerprints
            dialog.onResponse { continuation.resume(returning: $0 == "trust") }
            dialog.present(window.window)
        }
    }

    /// A small window with scp's own progress for the file it is sending, and Cancel.
    @MainActor
    private final class ProgressSheet {
        var onCancel: () -> Void = {}
        private let dialog: AlertDialog
        private let bar = ProgressBar()
        private let detail = Label("Connecting\u{2026}")
        private var closed = false

        init(title: String, window: AppWindow) {
            dialog = Dialogs.alert(heading: title, body: "", responses: [("cancel", "Cancel")], defaultResponse: "cancel")
            bar.setAccessibleLabel("Copy progress")
            detail.addCSSClass(.dimLabel)
            detail.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
            box.append(bar)
            box.append(detail)
            dialog.extraChild = box
            bar.pulse()
            dialog.onResponse { [weak self] _ in
                guard let self, !self.closed else { return }
                self.onCancel()
            }
            dialog.present(window.window)
            pulse()
        }

        /// Until scp reports its first percentage the bar just pulses.
        private func pulse() {
            MainContext.delay(ms: 250) { [weak self] in
                guard let self, !self.closed, self.bar.fraction == 0 else { return }
                self.bar.pulse()
                self.pulse()
            }
        }

        func show(_ update: SSHCopyProgress) {
            guard !closed else { return }
            bar.fraction = Double(update.percent) / 100
            detail.text = "\(update.fileName) \u{00B7} \(update.percent)% \u{00B7} \(update.speed) \u{00B7} \(update.remaining) left"
        }

        func close() {
            guard !closed else { return }
            closed = true
            _ = adw_dialog_close(dialog.castedPointer() as UnsafeMutablePointer<AdwDialog>)
        }
    }
}
