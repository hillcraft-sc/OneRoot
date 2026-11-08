import Foundation

/// Every file property the list view can show as a column, and how it's
/// sorted. `.name` is the anchor column: always visible, always first,
/// not user-removable. Everything else is optional and toggled on/off via
/// the column header's right-click menu (see `FileTableController`).
enum FileColumn: String, CaseIterable, Hashable {
    case name
    case dateModified
    case dateCreated
    case dateAdded
    case dateLastOpened
    case size
    case kind
    case tags
    case fileExtension
    /// The folder an item is in — shown on its own in Recents and Shared,
    /// whose items come from all over.
    case location

    var title: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateAdded: return "Date Added"
        case .dateLastOpened: return "Date Last Opened"
        case .size: return "Size"
        case .kind: return "Type"
        case .tags: return "Tags"
        case .fileExtension: return "Extension"
        case .location: return "Where"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 260
        case .dateModified, .dateCreated, .dateAdded, .dateLastOpened: return 160
        case .size: return 90
        case .kind: return 120
        case .tags: return 170
        case .fileExtension: return 80
        case .location: return 240
        }
    }

    var isRemovable: Bool { self != .name }

    /// The OneRoot layout's columns: what it is, when it changed, how big,
    /// and its tags.
    static let defaultVisible: [FileColumn] = [.name, .kind, .dateModified, .size, .tags]

    /// Ensures `.name` is present and first — the anchor column can't be
    /// removed or dragged out of place — while otherwise preserving
    /// `columns`' order exactly, including any custom order the user
    /// dragged columns into.
    static func normalized(_ columns: [FileColumn]) -> [FileColumn] {
        [.name] + columns.filter { $0 != .name }
    }
}
