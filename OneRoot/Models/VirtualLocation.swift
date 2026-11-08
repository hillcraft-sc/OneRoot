import Foundation

/// A place in the sidebar that isn't a folder: a list gathered from all
/// over the disk (Recents, Shared). The file list shows it like a folder,
/// but folder-only things (Paste, New Folder, Up, live watching) are off.
///
/// History, tabs, and sessions store locations as URLs, so each has one of
/// its own in the `oneroot:` scheme — never a file URL, so nothing can
/// mistake it for a real folder.
enum VirtualLocation: String, CaseIterable, Codable, Identifiable {
    case recents
    case shared

    var id: Self { self }

    static let scheme = "oneroot"

    var url: URL {
        URL(string: "\(Self.scheme):\(rawValue)") ?? URL(fileURLWithPath: "/")
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let location = VirtualLocation(rawValue: String(url.absoluteString.dropFirst(Self.scheme.count + 1)))
        else { return nil }
        self = location
    }

    var title: String {
        switch self {
        case .recents: return "Recents"
        case .shared: return "Shared"
        }
    }

    var systemImage: String {
        switch self {
        case .recents: return "clock"
        case .shared: return "person.2"
        }
    }

    /// Shown when the list is empty — saying what it covers, honestly.
    var emptyMessage: String {
        switch self {
        case .recents: return "Nothing opened in the last 30 days."
        case .shared: return "Nothing in iCloud Drive is shared. (Other cloud services don't tell macOS what's shared.)"
        }
    }
}
