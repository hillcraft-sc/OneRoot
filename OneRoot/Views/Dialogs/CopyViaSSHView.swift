import SwiftUI

/// Prompts for a remote destination and copies the given local files there
/// via `scp` (see `SSHCopyService`). Supports picking a saved destination
/// (host/port/username/path/private key, and optionally a Keychain-stored
/// password — see `SavedSSHDestinationsService`/`SSHCredentialsService`),
/// or a private key file directly, so lab/server logins that already work
/// key-only from Terminal don't need a password here either. The password
/// field is a fallback for when neither of those covers it: it's used for
/// whichever `ssh` would otherwise prompt for interactively — the account
/// password or the key's passphrase — since there's no tty here for it to
/// prompt on.
///
/// Touch ID/password gating (`SSHDeviceAuthenticationPreferenceService`)
/// happens before this view is even presented — see
/// `FileListView.requestSSHCopy` — since the saved-destinations list here
/// already surfaces which servers/credentials exist as soon as it's open.
struct CopyViaSSHView: View {
    @Environment(\.dismiss) private var dismiss
    let fileURLs: [URL]

    @State private var host = ""
    @State private var port = "22"
    @State private var username = NSUserName()
    @State private var remotePath = "~/"
    @State private var privateKeyPath = ""
    @State private var password = ""
    @State private var rememberPassword = false
    @State private var isCopying = false
    @State private var didFinish = false
    @State private var errorMessage: String?

    @State private var savedDestinations: [SavedSSHDestination] = []
    @State private var selectedDestinationID: SavedSSHDestination.ID?

    private let service = SSHCopyService()
    private let savedDestinationsService = SavedSSHDestinationsService()
    private let credentialsService = SSHCredentialsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            savedDestinationsList

            SSHDestinationFieldsView(
                host: $host,
                port: $port,
                username: $username,
                remotePath: $remotePath,
                privateKeyPath: $privateKeyPath,
                password: $password
            )
            .disabled(isCopying || didFinish)

            Toggle("Remember password in Keychain", isOn: $rememberPassword)
                .font(.caption)
                .disabled(isCopying || didFinish)

            Text("Leave the password blank if the private key above doesn't need a passphrase, or an SSH agent already has it unlocked.")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusView

            HStack {
                HelpButton(topic: .copyViaSSH)
                Spacer()
                if didFinish {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .disabled(isCopying)
                    Button(isCopying ? "Copying…" : "Copy") { copy() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isCopying || host.trimmingCharacters(in: .whitespaces).isEmpty || Int(port) == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            savedDestinations = savedDestinationsService.load()
            if privateKeyPath.isEmpty {
                privateKeyPath = SSHCopyService.defaultPrivateKeyPath() ?? ""
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if didFinish {
            Label("Copied to \(host).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isCopying {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(fileURLs.count == 1 ? "Copying \"\(fileURLs[0].lastPathComponent)\"…" : "Copying \(fileURLs.count) items…")
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var title: String {
        fileURLs.count == 1
            ? "Copy \"\(fileURLs[0].lastPathComponent)\" via SSH"
            : "Copy \(fileURLs.count) Items via SSH"
    }

    private var savedDestinationsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved Destinations")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(savedDestinations, selection: $selectedDestinationID) { destination in
                Text(destination.name)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        fillFields(from: destination)
                        copy()
                    }
            }
            .frame(height: 70)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            .onChange(of: selectedDestinationID) { _, _ in
                guard let destination = savedDestinations.first(where: { $0.id == selectedDestinationID }) else { return }
                fillFields(from: destination)
            }

            HStack(spacing: 8) {
                Button {
                    addCurrentAsFavorite()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    removeSelectedFavorite()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedDestinationID == nil)
            }
            .buttonStyle(.borderless)
        }
    }

    private func fillFields(from destination: SavedSSHDestination) {
        host = destination.host
        port = String(destination.port)
        username = destination.username
        remotePath = destination.remotePath
        privateKeyPath = destination.privateKeyPath ?? ""
        password = credentialsService.password(for: destination.id) ?? ""
        rememberPassword = !password.isEmpty
    }

    private func addCurrentAsFavorite() {
        guard let portNumber = Int(port) else { return }
        let destination = SavedSSHDestination(
            name: "\(username)@\(host)",
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            username: username.trimmingCharacters(in: .whitespaces),
            remotePath: remotePath.trimmingCharacters(in: .whitespaces),
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath
        )
        savedDestinations = savedDestinationsService.upsert(destination)
        selectedDestinationID = destination.id
        if rememberPassword, !password.isEmpty {
            credentialsService.savePassword(password, for: destination.id)
        }
    }

    private func removeSelectedFavorite() {
        guard let selectedDestinationID else { return }
        credentialsService.removePassword(for: selectedDestinationID)
        savedDestinations = savedDestinationsService.remove(id: selectedDestinationID)
        self.selectedDestinationID = nil
    }

    private func copy() {
        guard let portNumber = Int(port) else { return }
        errorMessage = nil
        isCopying = true
        let destination = SSHDestination(
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            username: username.trimmingCharacters(in: .whitespaces),
            remotePath: remotePath.trimmingCharacters(in: .whitespaces),
            privateKeyPath: privateKeyPath.trimmingCharacters(in: .whitespaces)
        )
        Task {
            do {
                try await service.copy(fileURLs, to: destination, password: password.isEmpty ? nil : password)
                isCopying = false
                didFinish = true
                if let selectedDestinationID, rememberPassword, !password.isEmpty {
                    credentialsService.savePassword(password, for: selectedDestinationID)
                }
            } catch {
                isCopying = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
