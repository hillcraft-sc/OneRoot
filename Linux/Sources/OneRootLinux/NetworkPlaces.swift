import Foundation
@testable import OneRoot

/// One row of the Network window.
struct NetworkPlace: Equatable {
    enum Kind { case favorite, found }
    var kind: Kind
    var title: String
    var address: String
    var favoriteID: UUID?

    var url: URL? { URL(string: address) }
}

/// What the Network window lists: your Favorites first, then the servers the
/// network announces, leaving out any announced server you already have as a
/// favorite (under its name or its IP address).
enum NetworkPlaces {
    /// A readable name: "timemachine on 192.168.1.20", or just the host.
    static func title(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let share = url.pathComponents.filter { $0 != "/" }.last
        return share.map { "\($0) on \(host)" } ?? host
    }

    /// The place, ignoring a trailing slash, the host's case and the scheme's default port.
    static func key(_ url: URL) -> String {
        let defaults = ["smb": 445, "sftp": 22, "ssh": 22, "ftp": 21, "nfs": 2049, "dav": 80, "davs": 443]
        let scheme = url.scheme?.lowercased() ?? ""
        var port = ""
        if let value = url.port, value != defaults[scheme] { port = ":\(value)" }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme)://\(url.host?.lowercased() ?? "")\(port)\(path)"
    }

    /// `aliases` maps a host name to every name and address it goes by (see `NetworkHostAliases`).
    static func combine(favorites: [SavedServer], found: [NetworkServer], aliases: [String: Set<String>]) -> [NetworkPlace] {
        func names(of host: String?) -> Set<String> {
            guard let host = host?.lowercased() else { return [] }
            return (aliases[host] ?? []).union([host])
        }
        var result: [NetworkPlace] = favorites.map { favorite in
            let isHostName = favorite.name == favorite.url.host
            return NetworkPlace(kind: .favorite, title: isHostName ? title(for: favorite.url) : favorite.name,
                                address: favorite.url.absoluteString, favoriteID: favorite.id)
        }
        var known = Set<String>()
        for place in result { known.formUnion(names(of: place.url?.host)) }
        for server in found {
            let host = URL(string: server.address)?.host
            guard known.isDisjoint(with: names(of: host)) else { continue }
            known.formUnion(names(of: host))
            result.append(NetworkPlace(kind: .found, title: server.name, address: server.address))
        }
        return result
    }
}
