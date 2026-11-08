import CAdwaita
import Foundation

/// A server is known by a name (`nas.local`) and by its address
/// (`192.168.1.20`), and which one you typed, or the network announced, varies.
/// A remembered login is kept under every name it is known by, so either finds it.
enum NetworkHostAliases {
    /// `host` (lower-cased) first, then the addresses it resolves to; a name that
    /// doesn't resolve in a few seconds is just itself. Off the main thread.
    static func accounts(for host: String) async -> [String] {
        let name = host.lowercased()
        let resolved = await withTaskGroup(of: [String]?.self) { group -> [String] in
            group.addTask { await Task.detached(priority: .userInitiated) { addresses(of: name) }.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
        return merged(name, resolved)
    }

    /// `name` then `addresses`, without repeats.
    static func merged(_ name: String, _ addresses: [String]) -> [String] {
        var seen = Set<String>()
        return ([name] + addresses).filter { seen.insert($0).inserted }
    }

    /// Numeric addresses `name` resolves to (link-local IPv6 dropped: it needs an interface).
    nonisolated static func addresses(of name: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &found) == 0, let first = found else { return [] }
        defer { freeaddrinfo(found) }
        var result: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let current = node {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(cString: buffer).lowercased()
                if !text.hasPrefix("fe80"), !result.contains(text) { result.append(text) }
            }
            node = current.pointee.ai_next
        }
        return Array(result.prefix(4))
    }
}
