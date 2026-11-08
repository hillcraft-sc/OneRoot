import Foundation
import Security

/// Stores SSH passwords/key passphrases in the Keychain, keyed by the
/// owning `SavedSSHDestination`'s `id` — mirrors `NetworkShareService`'s
/// Keychain use for SMB credentials. `SavedSSHDestinationsService` only
/// ever persists the non-secret fields; this is the only place a secret
/// touches disk, and it's the Keychain rather than `UserDefaults`.
struct SSHCredentialsService {
    private static let service = "com.oneroot.ssh"

    func savePassword(_ password: String, for destinationID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: destinationID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(newItem as CFDictionary, nil)
    }

    func password(for destinationID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: destinationID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }

    func removePassword(for destinationID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: destinationID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
