import Foundation

/// What sort of place a destination (or a folder-hierarchy root) is. Picks
/// its icon and which context-menu actions make sense for it.
enum DestinationKind: String, Codable {
    case home
    case applications
    case bootVolume
    case volume
    case networkVolume
    case cloud
    case pinned
    case trash
    /// A plain folder root — e.g. a folder the hierarchy fell back to.
    case folder
    /// Recents and Shared: lists, not folders (`VirtualLocation`). Never a
    /// hierarchy root.
    case recents
    case shared

    var isVirtual: Bool { self == .recents || self == .shared }

    /// The tag `FolderOutlineViewController` reads off a root `FileNode`'s
    /// `kind` to pick its icon and menu — the tree predates this enum.
    var nodeKindTag: String {
        switch self {
        case .home, .folder, .recents, .shared: return "Folder"
        case .applications: return "Applications"
        case .bootVolume: return "Boot Volume"
        case .volume: return "Volume"
        case .networkVolume: return "Network Volume"
        case .cloud: return "Cloud Storage"
        case .pinned: return "Pinned"
        case .trash: return "Trash"
        }
    }
}

/// One row of the global destination sidebar: a place to start working.
/// Shallow on purpose — choosing one roots the folder hierarchy there
/// instead of expanding in place.
struct Destination: Identifiable, Equatable {
    let url: URL
    let name: String
    let kind: DestinationKind
    /// Volumes and network shares that can be ejected or disconnected.
    var isEjectable: Bool = false

    var id: URL { url }

    var hierarchyRoot: HierarchyRoot {
        HierarchyRoot(url: url, name: name, kind: kind)
    }
}

/// A titled group of destinations. `id` stays stable so the sidebar keeps
/// its section identity and ordering across rebuilds.
struct DestinationSection: Identifiable, Equatable {
    let id: String
    /// Empty for the untitled top group (Home).
    let title: String
    let destinations: [Destination]
}
