import CLibSecret
import Foundation

/// Passwords in the desktop keyring (Secret Service via libsecret) — the
/// Linux side of what the Mac keeps in the Keychain. Only secrets go here;
/// everything else (hosts, users, paths) stays in the shared saved-server and
/// saved-destination lists.
///
/// A machine without a keyring (a bare window manager, a container) is a
/// normal case, not a crash: `store` reports it, `password` returns nil.
struct KeyringService {
    enum Failure: Error, Equatable, LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self {
            case .unavailable(let detail):
                return "The desktop keyring isn\u{2019}t available, so the password can\u{2019}t be remembered. \(detail)"
            }
        }
    }

    let service: String

    static let ssh = KeyringService(service: "com.oneroot.ssh")
    static let network = KeyringService(service: "com.oneroot.network")

    func store(_ secret: String, account: String, label: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let ok = oneroot_secret_store(service, account, label, secret, &message)
        defer { if let message { g_free(message) } }
        guard ok == 1 else {
            throw Failure.unavailable(message.map { String(cString: $0) } ?? "")
        }
    }

    func password(account: String) -> String? {
        var message: UnsafeMutablePointer<CChar>?
        guard let raw = oneroot_secret_lookup(service, account, &message) else {
            if let message { g_free(message) }
            return nil
        }
        defer { secret_password_free(raw) }
        return String(cString: raw)
    }

    func remove(account: String) {
        var message: UnsafeMutablePointer<CChar>?
        _ = oneroot_secret_clear(service, account, &message)
        if let message { g_free(message) }
    }
}
