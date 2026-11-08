import SwiftUI

/// The Host/Port/Username/Remote-Path/Private-Key/Password fields shared by
/// the "Copy via SSH" dialog and the Settings SSH destination editor — kept
/// in one place so the two forms can't drift out of sync.
struct SSHDestinationFieldsView: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var username: String
    @Binding var remotePath: String
    @Binding var privateKeyPath: String
    @Binding var password: String
    var passwordLabel = "Password or key passphrase (optional)"

    @State private var showingChoosePrivateKey = false

    var body: some View {
        Group {
            TextField("Host", text: $host)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            HStack {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            TextField("Remote path (e.g. ~/Uploads/)", text: $remotePath)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            HStack {
                TextField("Private key (e.g. ~/.ssh/id_ed25519)", text: $privateKeyPath)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Button("Browse…", action: choosePrivateKey)
            }

            SecureField(passwordLabel, text: $password)
                .textFieldStyle(.roundedBorder)
        }
        .sheet(isPresented: $showingChoosePrivateKey) {
            FileChooserView(
                startingAt: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh"),
                canChooseFiles: true,
                canChooseDirectories: false,
                showsHiddenFiles: true
            ) { url in
                privateKeyPath = url.path
            }
        }
    }

    private func choosePrivateKey() {
        showingChoosePrivateKey = true
    }
}
