import Foundation

/// A named set of real folders for one project — "Project Phoenix": its
/// documents here, its designs on the NAS, its repository there. Not a
/// folder and not a merged view: choosing it shows each folder as its own
/// root in the hierarchy, where it really is.
struct Workspace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol shown in the sidebar.
    var symbolName: String = Workspace.symbolChoices[0]
    /// In the order the hierarchy shows them.
    var folders: [URL] = []

    static let symbolChoices = [
        "square.stack.3d.up", "folder", "briefcase", "hammer",
        "paintbrush", "doc.text", "photo", "music.note", "star", "house",
    ]

    /// Whether `url` is one of the folders or somewhere inside one.
    func contains(_ url: URL) -> Bool {
        folders.contains { HierarchyRootResolver.isAncestor($0, of: url) }
    }

    /// `folders` plus each of `urls` it doesn't already cover — one of its
    /// folders, or inside one, is already in the Workspace.
    func addingFolders(_ urls: [URL]) -> Workspace {
        var copy = self
        for url in urls where !copy.contains(url) {
            copy.folders.append(url)
        }
        return copy
    }

    /// The hierarchy roots: one per folder, named after it — with the
    /// folder it's in added when two would otherwise read the same
    /// ("Design (Phoenix)", "Design (Archive)").
    var hierarchyRoots: [HierarchyRoot] {
        let names = folders.map(\.lastPathComponent)
        return folders.map { folder in
            var name = folder.lastPathComponent
            if names.filter({ $0 == name }).count > 1 {
                name += " (\(folder.deletingLastPathComponent().lastPathComponent))"
            }
            return HierarchyRoot(url: folder, name: name, kind: .folder)
        }
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }
}
