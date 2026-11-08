import Foundation

/// A file or folder in the tree/list. Reference type so the outline view can
/// mutate `children` in place once loaded, without SwiftUI needing to observe
/// every mutation — the AppKit controllers are the source of truth for tree
/// state (see CLAUDE.md gotchas).
final class FileNode: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// True for `.app` bundles and other macOS packages — directories on
    /// disk that should behave like a single launchable/openable file
    /// (Open/double-click launches it) rather than something to navigate
    /// into.
    let isPackage: Bool
    let size: Int64?
    let modificationDate: Date?
    let kind: String?
    let creationDate: Date?
    let dateAdded: Date?
    let lastOpenedDate: Date?
    let tags: [String]

    /// `nil` means "not yet loaded from disk". Populated lazily on first
    /// expansion/listing.
    var children: [FileNode]?

    var id: URL { url }

    var fileExtension: String { url.pathExtension }

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        size: Int64?,
        modificationDate: Date?,
        kind: String?,
        creationDate: Date? = nil,
        dateAdded: Date? = nil,
        lastOpenedDate: Date? = nil,
        tags: [String] = [],
        children: [FileNode]? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.size = size
        self.modificationDate = modificationDate
        self.kind = kind
        self.creationDate = creationDate
        self.dateAdded = dateAdded
        self.lastOpenedDate = lastOpenedDate
        self.tags = tags
        self.children = children
    }

    /// A copy with `lastOpenedDate` set — Recents (and, if chosen in
    /// Settings, every list) uses Spotlight's last-used date rather than
    /// the file's access time. `nil`: never opened, as far as Spotlight knows.
    func withLastOpened(_ date: Date?) -> FileNode {
        FileNode(
            url: url, name: name, isDirectory: isDirectory, isPackage: isPackage, size: size,
            modificationDate: modificationDate, kind: kind, creationDate: creationDate, dateAdded: dateAdded,
            lastOpenedDate: date, tags: tags, children: children
        )
    }

    /// Whether "Open" should navigate into this node as a folder rather than
    /// launch/extract/hand it off — true for any non-package directory, and
    /// for a package only when explicitly asked to browse into it (Option-⌘O
    /// / Option-Open) instead of launching it.
    func isNavigable(browsePackage: Bool) -> Bool {
        guard isDirectory else { return false }
        guard isPackage else { return true }
        return browsePackage
    }
}
