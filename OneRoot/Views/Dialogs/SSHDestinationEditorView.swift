import SwiftUI

/// Add/edit sheet for a single saved SSH destination, presented from
/// `SSHSettingsView`. Reuses `SSHDestinationFieldsView` for the actual
/// fields so this and `CopyViaSSHView` can't drift apart.
struct SSHDestinationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: SavedSSHDestination
    var onSave: (SavedSSHDestination) -> Void

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var remotePath: String
    @State private var privateKeyPath: String
    @State private var password = ""
    @State private var isInstallingKey = false
    @State private var installKeySucceeded = false
    @State private var installKeyMessage: String?
    @State private var showingInstallKeyPasswordPrompt = false

    private let credentialsService = SSHCredentialsService()
    private let copyService = SSHCopyService()

    init(destination: SavedSSHDestination, onSave: @escaping (SavedSSHDestination) -> Void) {
        self.destination = destination
        self.onSave = onSave
        _name = State(initialValue: destination.name)
        _host = State(initialValue: destination.host)
        _port = State(initialValue: String(destination.port))
        _username = State(initialValue: destination.username)
        _remotePath = State(initialValue: destination.remotePath)
        _privateKeyPath = State(initialValue: destination.privateKeyPath ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSH Destination")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            SSHDestinationFieldsView(
                host: $host,
                port: $port,
                username: $username,
                remotePath: $remotePath,
                privateKeyPath: $privateKeyPath,
                password: $password,
                passwordLabel: "Password or key passphrase (optional, stored in Keychain)"
            )

            installKeySection

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || Int(port) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { password = credentialsService.password(for: destination.id) ?? "" }
        .sheet(isPresented: $showingInstallKeyPasswordPrompt) {
            InstallKeyPasswordPromptView(username: username, host: host) { accountPassword in
                installKey(accountPassword: accountPassword)
            }
        }
    }

    private var installKeySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(isInstallingKey ? "Installing…" : "Install Key on Server…") { showingInstallKeyPasswordPrompt = true }
                    .disabled(
                        isInstallingKey
                            || host.trimmingCharacters(in: .whitespaces).isEmpty
                            || Int(port) == nil
                            || privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                if isInstallingKey {
                    ProgressView().controlSize(.small)
                }
            }
            Text("Only needed if the server doesn't already have this key. Safe to run even if it's already there.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let installKeyMessage {
                ScrollView {
                    Text(installKeyMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(installKeySucceeded ? .green : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private func save() {
        guard let portNumber = Int(port) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let updated = SavedSSHDestination(
            id: destination.id,
            name: trimmedName.isEmpty ? host : trimmedName,
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            username: username.trimmingCharacters(in: .whitespaces),
            remotePath: remotePath.trimmingCharacters(in: .whitespaces),
            privateKeyPath: privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty ? nil : privateKeyPath
        )
        if password.isEmpty {
            credentialsService.removePassword(for: destination.id)
        } else {
            credentialsService.savePassword(password, for: destination.id)
        }
        onSave(updated)
        dismiss()
    }

    private func installKey(accountPassword: String) {
        guard let portNumber = Int(port) else { return }
        isInstallingKey = true
        installKeyMessage = nil
        let destination = SSHDestination(
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            username: username.trimmingCharacters(in: .whitespaces),
            remotePath: remotePath.trimmingCharacters(in: .whitespaces),
            privateKeyPath: privateKeyPath.trimmingCharacters(in: .whitespaces)
        )
        Task {
            do {
                try await copyService.installKey(to: destination, password: accountPassword.isEmpty ? nil : accountPassword)
                isInstallingKey = false
                installKeySucceeded = true
                installKeyMessage = "Key installed on \(destination.host)."
            } catch {
                isInstallingKey = false
                installKeySucceeded = false
                installKeyMessage = error.localizedDescription
            }
        }
    }
}

/// Small sheet-based prompt for the "Install Key on Server" account
/// password — deliberately a sheet, not `.alert`, because `.alert`
/// presented from a sheet that's itself inside the `Settings` scene
/// doesn't reliably show up on macOS, even though the identical `.alert`
/// pattern works fine from the main window (e.g. the Rename dialog). This
/// exact sheet-on-sheet nesting, on the other hand, is already proven to
/// work here — `SSHDestinationEditorView` itself is one.
private struct InstallKeyPasswordPromptView: View {
    @Environment(\.dismiss) private var dismiss
    let username: String
    let host: String
    var onInstall: (String) -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Key on Server")
                .font(.headline)

            Text("This logs in once with \(username)'s account password on \(host) to add the key. That password isn't saved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("Account password for \(username)@\(host)", text: $password)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Install") {
                    onInstall(password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
