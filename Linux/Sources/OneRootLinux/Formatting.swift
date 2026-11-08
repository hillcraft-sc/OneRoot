import Foundation
@testable import OneRoot

/// Text the views show, in one place.
enum Formatting {
    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func size(_ value: Int64) -> String { bytes.string(fromByteCount: value) }

    static func date(_ date: Date?) -> String {
        date.map { FileDateFormat.string(from: $0) } ?? ""
    }

    /// "6 items, 1 folder, 5 files", "1 of 2 items, 0 folders, 2 files"
    /// (the Mac status line's wording).
    static func summary(items: Int, folders: Int, selected: Int) -> String {
        func count(_ number: Int, _ singular: String, _ plural: String) -> String {
            "\(number) \(number == 1 ? singular : plural)"
        }
        let base = "\(count(items, "item", "items")), \(count(folders, "folder", "folders")), \(count(items - folders, "file", "files"))"
        return selected > 0 ? "\(selected) of \(base)" : base
    }

    /// The text of a list cell for `column`.
    static func cell(_ node: FileNode, _ column: FileColumn, folderSizes: [URL: Int64]) -> String {
        switch column {
        case .name: return node.name
        case .dateModified: return date(node.modificationDate)
        case .dateCreated: return date(node.creationDate)
        case .dateAdded: return date(node.dateAdded)
        case .dateLastOpened: return date(node.lastOpenedDate)
        case .size:
            if node.isDirectory { return folderSizes[node.url].map(size) ?? "—" }
            return node.size.map(size) ?? ""
        case .kind: return node.kind ?? ""
        case .tags: return node.tags.joined(separator: ", ")
        case .fileExtension: return node.isDirectory ? "" : node.fileExtension
        case .location: return node.url.deletingLastPathComponent().path
        }
    }
}
