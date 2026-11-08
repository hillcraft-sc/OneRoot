import Foundation

/// Decides which folder the hierarchy pane should be rooted at for a given
/// location. Pure — no disk access beyond resolving symlinks in paths.
///
/// The rules, in order:
/// 1. If the current root is still a destination and still contains the
///    location, keep it. A tab opened from Home stays rooted at Home while
///    you browse inside it, even into a folder that's also pinned. A root
///    that stopped being a destination (unpinned, unmounted) doesn't stick.
/// 2. Otherwise, the candidate (a destination) that contains the location
///    most specifically — e.g. a pinned `~/Projects/Phoenix` beats Home.
///    Applications only wins for paths actually inside `/Applications`.
/// 3. Otherwise, the filesystem root, so the hierarchy is never empty.
enum HierarchyRootResolver {
    static func root(
        for location: URL,
        current: HierarchyRoot?,
        candidates: [HierarchyRoot]
    ) -> HierarchyRoot {
        if let current, current.contains(location),
           // The candidate rather than `current` itself, to pick up a
           // refreshed name (a renamed volume).
           let stillCandidate = candidates.first(where: { sameLocation($0.url, current.url) }) {
            return stillCandidate
        }
        let best = candidates
            .filter { $0.contains(location) }
            .max { components($0.url).count < components($1.url).count }
        return best ?? fallbackRoot
    }

    static let fallbackRoot = HierarchyRoot(url: URL(fileURLWithPath: "/", isDirectory: true), name: "/", kind: .bootVolume)

    static func isAncestor(_ ancestor: URL, of url: URL) -> Bool {
        components(url).starts(with: components(ancestor))
    }

    static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        components(lhs) == components(rhs)
    }

    private static func components(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}
