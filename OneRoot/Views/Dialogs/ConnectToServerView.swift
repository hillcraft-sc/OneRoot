import SwiftUI

/// Matches Finder's ⌘K dialog: an address field plus optional credentials.
/// On success the share mounts under /Volumes and is picked up by the same
/// mount-notification path as USB drives (see `VolumeService`), so it just
/// appears in the sidebar — this view only needs to report the mount point
/// back so the caller can navigate to it.
struct ConnectToServerView: View {
    @Environment(\.dismiss) private var dismiss
    var onConnect: (URL) -> Void

    @State private var addressText = "smb://"
    @State private var username = ""
    @State private var password = ""
    @State private var rememberCredentials = true
    @State private var isConnecting = false
    @State private var errorMessage: String?

    @State private var savedServers: [SavedServer] = []
    @State private var selectedServerID: SavedServer.ID?

    private let networkShareService = NetworkShareService()
    private let savedServersService = SavedServersService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Server")
                .font(.headline)

            TextField("smb://server/share", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onChange(of: addressText, prefillSavedCredentialsIfAvailable)

            favoriteServersList

            TextField("Username (optional)", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password (optional)", text: $password)
                .textFieldStyle(.roundedBorder)

            Toggle("Remember password in Keychain", isOn: $rememberCredentials)
                .font(.caption)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                HelpButton(topic: .networkShares)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isConnecting ? "Connecting…" : "Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnecting || addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { savedServers = savedServersService.load() }
    }

    private var favoriteServersList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Favorite Servers")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(savedServers, selection: $selectedServerID) { server in
                Text(server.name)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        addressText = server.url.absoluteString
                        connect()
                    }
            }
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            .onChange(of: selectedServerID, fillAddressFromSelectedFavorite)

            HStack(spacing: 8) {
                Button {
                    addCurrentAddressAsFavorite()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isValidAddress(addressText))

                Button {
                    removeSelectedFavorite()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedServerID == nil)
            }
            .buttonStyle(.borderless)
        }
    }

    private func fillAddressFromSelectedFavorite() {
        guard let server = savedServers.first(where: { $0.id == selectedServerID }) else { return }
        addressText = server.url.absoluteString
    }

    private func isValidAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme != nil && url.host != nil
    }

    private func addCurrentAddressAsFavorite() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, let host = url.host else { return }
        let sharePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = sharePath.isEmpty ? host : "\(host) — \(sharePath)"
        savedServers = savedServersService.add(SavedServer(name: name, url: url))
    }

    private func removeSelectedFavorite() {
        guard let selectedServerID else { return }
        savedServers = savedServersService.remove(id: selectedServerID)
        self.selectedServerID = nil
    }

    private func prefillSavedCredentialsIfAvailable() {
        guard let host = URL(string: addressText.trimmingCharacters(in: .whitespaces))?.host,
              let saved = networkShareService.savedCredentials(host: host)
        else { return }
        username = saved.username
        password = saved.password
    }

    private func connect() {
        errorMessage = nil
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            errorMessage = "That doesn't look like a valid address, e.g. smb://server/share."
            return
        }

        let credentials = username.isEmpty ? nil : NetworkCredentials(username: username, password: password)
        isConnecting = true
        Task {
            do {
                let mountPoints = try await networkShareService.mount(url: url, credentials: credentials)
                if rememberCredentials, let credentials, let host = url.host {
                    networkShareService.saveCredentials(host: host, username: credentials.username, password: credentials.password)
                }
                isConnecting = false
                if let mountPoint = mountPoints.first {
                    onConnect(mountPoint)
                }
                dismiss()
            } catch {
                isConnecting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
