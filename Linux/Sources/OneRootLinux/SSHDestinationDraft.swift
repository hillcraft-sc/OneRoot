import Foundation
@testable import OneRoot

/// What the SSH forms (Copy via SSH, Settings ▸ SSH) hold while being
/// edited: the text of each field, checked before anything runs or is saved.
struct SSHDestinationDraft: Equatable {
    var host = ""
    var port = "22"
    var username = NSUserName()
    var remotePath = "~/"
    var privateKeyPath = ""
    var password = ""
    var remembersPassword = false

    init() {}

    init(_ saved: SavedSSHDestination, password: String = "") {
        host = saved.host
        port = String(saved.port)
        username = saved.username
        remotePath = saved.remotePath
        privateKeyPath = saved.privateKeyPath ?? ""
        self.password = password
        remembersPassword = !password.isEmpty
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var trimmedUser: String { username.trimmingCharacters(in: .whitespaces) }

    /// Why this can't be used yet, in words for the form, or nil when it can.
    var problem: String? {
        if trimmedHost.isEmpty { return "Enter the server\u{2019}s host name or address." }
        if trimmedHost.contains(where: \.isWhitespace) { return "A host name has no spaces." }
        guard let number = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(number) else {
            return "The port is a number from 1 to 65535 (SSH usually uses 22)."
        }
        _ = number
        if trimmedUser.isEmpty { return "Enter the user name to log in as." }
        return nil
    }

    var isValid: Bool { problem == nil }

    /// The remote folder: `~/` when left empty.
    var effectiveRemotePath: String {
        let path = remotePath.trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? "~/" : path
    }

    func destination() -> SSHDestination? {
        guard isValid, let number = Int(port.trimmingCharacters(in: .whitespaces)) else { return nil }
        return SSHDestination(
            host: trimmedHost, port: number, username: trimmedUser, remotePath: effectiveRemotePath,
            privateKeyPath: privateKeyPath.trimmingCharacters(in: .whitespaces)
        )
    }

    /// A destination to save, named `user@host` unless given a name.
    func saved(id: UUID = UUID(), name: String? = nil) -> SavedSSHDestination? {
        guard let destination = destination() else { return nil }
        let trimmedName = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return SavedSSHDestination(
            id: id, name: trimmedName.isEmpty ? "\(destination.username)@\(destination.host)" : trimmedName,
            host: destination.host, port: destination.port, username: destination.username,
            remotePath: destination.remotePath,
            privateKeyPath: (destination.privateKeyPath ?? "").isEmpty ? nil : destination.privateKeyPath
        )
    }
}
