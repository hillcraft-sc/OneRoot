import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Icons for files and places, from the icon theme through GIO's content
/// types — the same icons Nautilus and Dolphin show. Kept per extension.
@MainActor
enum FileIcons {
    private static var byExtension: [String: OpaquePointer] = [:]
    private static let folder: OpaquePointer? = g_themed_icon_new("folder")

    static func icon(for node: FileNode) -> OpaquePointer? {
        if node.isDirectory { return folder }
        let ext = node.url.pathExtension.lowercased()
        if let cached = byExtension[ext] { return cached }
        guard let type = g_content_type_guess(node.name, nil, 0, nil) else { return nil }
        defer { g_free(type) }
        guard let icon = g_content_type_get_icon(type) else { return nil }
        byExtension[ext] = icon
        return icon
    }

    /// The icon for a file known only by its URL (a search or duplicate
    /// result): picked from the name alone, no disk access.
    static func set(_ image: Image, toFileAt url: URL) {
        let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: false, size: nil, modificationDate: nil, kind: nil)
        set(image, to: node)
    }

    static func set(_ image: Image, to node: FileNode) {
        if let icon = icon(for: node) {
            gtk_image_set_from_gicon(image.opaquePointer, icon)
        } else {
            image.iconName = "text-x-generic"
        }
    }

    /// A symbolic icon for a sidebar destination.
    static func symbolicName(for destination: Destination) -> String {
        switch destination.kind {
        case .home: return "user-home-symbolic"
        case .bootVolume: return "drive-harddisk-symbolic"
        case .volume: return destination.isEjectable ? "drive-removable-media-symbolic" : "drive-harddisk-symbolic"
        case .networkVolume: return "folder-remote-symbolic"
        case .cloud: return "folder-remote-symbolic"
        case .trash: return "user-trash-symbolic"
        case .applications: return "application-x-executable-symbolic"
        case .recents: return "document-open-recent-symbolic"
        case .shared: return "folder-publicshare-symbolic"
        case .pinned, .folder: return folderSymbolicName(for: destination.url)
        }
    }

    /// Desktop, Documents, … get their own icons, as in Nautilus.
    static func folderSymbolicName(for url: URL) -> String {
        userFolderIcons[url.standardizedFileURL.path] ?? "folder-symbolic"
    }

    private static let userFolderIcons: [String: String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ["DESKTOP": "user-desktop-symbolic", "DOCUMENTS": "folder-documents-symbolic",
                     "DOWNLOAD": "folder-download-symbolic", "MUSIC": "folder-music-symbolic",
                     "PICTURES": "folder-pictures-symbolic", "VIDEOS": "folder-videos-symbolic"]
        let file = home.appendingPathComponent(".config/user-dirs.dirs")
        let folders = (try? String(contentsOf: file, encoding: .utf8)).map { XDGUserDirectories.parse($0, home: home) } ?? [:]
        var icons: [String: String] = [:]
        for (key, url) in folders { if let name = names[key] { icons[url.path] = name } }
        return icons
    }()
}
