import Foundation

/// The folder the hierarchy pane is rooted at for a tab — usually the
/// destination it was opened from, or the nearest one containing where the
/// tab is now (see `HierarchyRootResolver`). Saved with the session.
struct HierarchyRoot: Codable, Equatable {
    let url: URL
    let name: String
    let kind: DestinationKind

    /// Whether `other` is this root or somewhere inside it. Compared with
    /// symlinks resolved, since FSEvents and some mount paths report the
    /// resolved form (`/private/var/…`) and others don't (`/var/…`).
    func contains(_ other: URL) -> Bool {
        HierarchyRootResolver.isAncestor(url, of: other)
    }
}
