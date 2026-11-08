import SwiftUI

/// Manage saved "Copy via SSH" destinations (see
/// `SavedSSHDestinationsService`) — lets destinations set up from that
/// dialog be reviewed, edited, or removed without going back through it.
/// Passwords/passphrases live in the Keychain (`SSHCredentialsService`),
/// never in this list.
struct SSHSettingsView: View {
    @State private var destinations: [SavedSSHDestination] = []
    @State private var selectedID: SavedSSHDestination.ID?
    @State private var editingDestination: SavedSSHDestination?
    @State private var requireDeviceAuthentication = true

    private let destinationsService = SavedSSHDestinationsService()
    private let credentialsService = SSHCredentialsService()
    private let deviceAuthenticationPreference = SSHDeviceAuthenticationPreferenceService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                Section {
                    Toggle("Require Touch ID or password before SSH copies", isOn: $requireDeviceAuthentication)
                        .onChange(of: requireDeviceAuthentication) { _, newValue in
                            deviceAuthenticationPreference.setEnabled(newValue)
                        }
                } footer: {
                    Text("Adds a Touch ID/password check before \u{201C}Copy via SSH\u{201D} runs, since a saved destination may include a stored password or key passphrase.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Destinations")
                    .font(.headline)
                    .padding(.horizontal, 4)
                destinationsCard
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
        .onAppear {
            destinations = destinationsService.load()
            requireDeviceAuthentication = deviceAuthenticationPreference.isEnabled()
        }
        .sheet(item: $editingDestination) { destination in
            SSHDestinationEditorView(destination: destination) { saved in
                destinations = destinationsService.upsert(saved)
                selectedID = saved.id
            }
        }
    }

    /// A bordered list with a +/-/Edit toolbar strip along the bottom —
    /// the classic "editable list" idiom macOS itself uses for exactly
    /// this shape of settings (Keychain Access' item list, Mail's rules,
    /// Users & Groups' account list, …) — rather than a bare `List` with
    /// buttons floating loose underneath it.
    private var destinationsCard: some View {
        VStack(spacing: 0) {
            if destinations.isEmpty {
                Text("Destinations you save from \u{201C}Copy via SSH\u{201D} appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                List(destinations, selection: $selectedID) { destination in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.name)
                        Text("\(destination.username)@\(destination.host):\(destination.port) \u{2192} \(destination.remotePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(destination.id)
                    .onTapGesture(count: 2) { editingDestination = destination }
                }
                .frame(minHeight: 160)
            }

            Divider()

            HStack(spacing: 2) {
                Button {
                    editingDestination = SavedSSHDestination(
                        name: "New Destination",
                        host: "",
                        username: NSUserName(),
                        remotePath: "~/",
                        privateKeyPath: SSHCopyService.defaultPrivateKeyPath()
                    )
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                Button {
                    removeSelected()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .disabled(selectedID == nil)
                Spacer()
                Button("Edit\u{2026}") {
                    editingDestination = destinations.first { $0.id == selectedID }
                }
                .disabled(selectedID == nil)
                .padding(.trailing, 6)
            }
            .buttonStyle(.borderless)
            .padding(4)
            .background(.quaternary.opacity(0.4))
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private func removeSelected() {
        guard let selectedID else { return }
        credentialsService.removePassword(for: selectedID)
        destinations = destinationsService.remove(id: selectedID)
        self.selectedID = nil
    }
}
