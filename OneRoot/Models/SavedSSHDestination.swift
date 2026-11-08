import Foundation

/// A saved "Copy via SSH" destination — host/port/username/remote path plus
/// an optional path to a private key file. Passwords/passphrases are never
/// stored here; see `SSHCredentialsService` for the Keychain side, keyed by
/// this destination's `id`.
struct SavedSSHDestination: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var remotePath: String
    var privateKeyPath: String?

    init(id: UUID = UUID(), name: String, host: String, port: Int = 22, username: String, remotePath: String, privateKeyPath: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.privateKeyPath = privateKeyPath
    }
}
