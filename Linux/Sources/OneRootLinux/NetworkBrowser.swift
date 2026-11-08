import CAdwaita
import Foundation

/// A server GVfs found on the local network (Avahi/DNS-SD, Windows
/// workgroups): a name for people and the address Connect to Server takes.
struct NetworkServer: Equatable, Sendable {
    var name: String
    var address: String

    /// "SMB", "SFTP", … from the address.
    var kind: String {
        address.split(separator: ":").first.map { $0.uppercased() } ?? ""
    }
}

/// Lists the servers GVfs sees at `network:///`, the location GNOME Files
/// calls Network. Reading happens off the main thread.
enum NetworkBrowser {
    /// Turns what GVfs listed into servers: entries with no usable address
    /// are dropped, duplicates merged, names sorted.
    static func servers(from items: [(name: String, target: String?)]) -> [NetworkServer] {
        var seen = Set<String>()
        var result: [NetworkServer] = []
        for item in items {
            guard let target = item.target?.trimmingCharacters(in: .whitespaces), !target.isEmpty,
                  target.contains("://"), !target.hasPrefix("network:"), seen.insert(target).inserted else { continue }
            let name = item.name.trimmingCharacters(in: .whitespaces)
            result.append(NetworkServer(name: name.isEmpty ? target : name, address: target))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    struct Unavailable: LocalizedError {
        var errorDescription: String?
    }

    static func discover() async -> Result<[NetworkServer], Unavailable> {
        await Task.detached(priority: .userInitiated) { () -> Result<[NetworkServer], Unavailable> in
            let location = g_file_new_for_uri("network:///")
            defer { g_object_unref(UnsafeMutableRawPointer(location)) }
            var error: UnsafeMutablePointer<GError>?
            guard let enumerator = g_file_enumerate_children(location, "standard::display-name,standard::target-uri", GFileQueryInfoFlags(rawValue: 0), nil, &error) else {
                let message = error.map { String(cString: $0.pointee.message) } ?? "Network browsing isn\u{2019}t available."
                if let error { g_error_free(error) }
                return .failure(Unavailable(errorDescription: message))
            }
            defer { g_object_unref(UnsafeMutableRawPointer(enumerator)) }
            var items: [(name: String, target: String?)] = []
            while let info = g_file_enumerator_next_file(enumerator, nil, nil) {
                let name = g_file_info_get_display_name(info).map { String(cString: $0) } ?? ""
                let target = g_file_info_get_attribute_string(info, "standard::target-uri").map { String(cString: $0) }
                items.append((name, target))
                g_object_unref(UnsafeMutableRawPointer(info))
            }
            return .success(servers(from: items))
        }.value
    }
}
