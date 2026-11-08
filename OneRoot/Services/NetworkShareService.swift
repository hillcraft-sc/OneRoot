import Darwin
import Foundation
import NetFS
import Security

struct NetworkCredentials {
    let username: String
    let password: String
}

enum NetworkShareError: LocalizedError {
    case mountFailed(status: Int32)
    case noMountPointReturned

    var errorDescription: String? {
        switch self {
        case .mountFailed(let status):
            if let message = SecCopyErrorMessageString(OSStatus(status), nil) as String? {
                return message
            }
            return "Couldn't connect (error \(status))."
        case .noMountPointReturned:
            return "Connected, but no mount point was returned."
        }
    }
}

/// Mounts SMB/AFP/NFS shares via the NetFS framework — this is exactly what
/// Finder's Connect to Server (⌘K) uses under the hood. Wraps
/// `NetFSMountURLSync`'s C-style out-parameter signature in a clean async
/// Swift function; the C ugliness stays contained here (see CLAUDE.md
/// gotchas). Credentials are optionally stored in the Keychain for reconnect.
struct NetworkShareService {
    /// Mounts `url` and returns the resulting local mount point(s). Passes
    /// `kNAUIOptionAllowUI` so the system's native auth prompt appears if the
    /// supplied credentials are missing or wrong, matching Finder's behavior.
    ///
    /// If `url` is already mounted, `NetFSMountURLSync` fails with `EEXIST`
    /// rather than returning the existing mount point — that's treated as
    /// success here (reconnecting to an already-connected favorite server
    /// should just navigate there, not show an error).
    func mount(url: URL, credentials: NetworkCredentials?) async throws -> [URL] {
        if let existing = Self.existingMountPoint(for: url) {
            return [existing]
        }
        return try await Task.detached(priority: .userInitiated) {
            let openOptions = NSMutableDictionary()
            openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI
            let mountOptions = NSMutableDictionary()

            var mountPointsRef: Unmanaged<CFArray>?
            let status = NetFSMountURLSync(
                url as CFURL,
                nil,
                credentials?.username as CFString?,
                credentials?.password as CFString?,
                openOptions,
                mountOptions,
                &mountPointsRef
            )

            guard status == 0 else {
                if status == EEXIST, let existing = Self.existingMountPoint(for: url) {
                    return [existing]
                }
                throw NetworkShareError.mountFailed(status: status)
            }
            guard let mountPoints = mountPointsRef?.takeRetainedValue() as? [String], !mountPoints.isEmpty else {
                throw NetworkShareError.noMountPointReturned
            }
            return mountPoints.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }.value
    }

    /// Finds a currently-mounted volume whose network origin matches `url`,
    /// by comparing `.volumeURLForRemountingKey` — the same resource key
    /// `VolumeService` reads for volumes generally, here narrowed to network
    /// mounts that trace back to this address.
    private static func existingMountPoint(for url: URL) -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        return volumes.first { volume in
            guard let remountURL = try? volume.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting else {
                return false
            }
            return remountURL.host == url.host && remountURL.path == url.path
        }
    }

    // MARK: Keychain

    func saveCredentials(host: String, username: String, password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(newItem as CFDictionary, nil)
    }

    func savedCredentials(host: String) -> NetworkCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return NetworkCredentials(username: account, password: password)
    }
}
