import Foundation

/// A Workspace stores its icon as an SF Symbol name (the Mac's choice, kept
/// so the saved Workspaces mean the same on both); on Linux each choice maps
/// to the freedesktop symbolic icon that looks closest.
enum WorkspaceIcons {
    static let linuxNames: [String: String] = [
        "square.stack.3d.up": "view-grid-symbolic",
        "folder": "folder-symbolic",
        "briefcase": "folder-documents-symbolic",
        "hammer": "applications-engineering-symbolic",
        "paintbrush": "applications-graphics-symbolic",
        "doc.text": "text-x-generic-symbolic",
        "photo": "image-x-generic-symbolic",
        "music.note": "audio-x-generic-symbolic",
        "star": "starred-symbolic",
        "house": "user-home-symbolic",
    ]

    static let fallback = "view-grid-symbolic"

    static func iconName(for symbol: String) -> String {
        linuxNames[symbol] ?? fallback
    }

    /// A short spoken name for the choice.
    static func title(for symbol: String) -> String {
        switch symbol {
        case "square.stack.3d.up": return "Stack"
        case "doc.text": return "Document"
        case "music.note": return "Music"
        default: return symbol.prefix(1).uppercased() + symbol.dropFirst()
        }
    }
}
