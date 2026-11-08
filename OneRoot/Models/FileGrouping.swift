import Foundation

/// Shared "Arrange By" rules for the file list, mirroring Finder's list-view
/// grouping. `FileListViewModel` uses `rank`/`label` together to keep same-
/// group nodes contiguous after sorting; `FileTableController` uses `label`
/// alone to know where a new section header belongs, since the view model
/// already guarantees matching labels are contiguous.
enum FileGrouping {
    static func group(for node: FileNode, by field: FileColumn) -> (rank: Int, label: String) {
        switch field {
        case .name:
            guard let first = node.name.first, first.isLetter || first.isNumber else { return (0, "#") }
            return (0, String(first).uppercased())
        case .kind:
            return (0, node.isDirectory ? "Folders" : (node.kind ?? "Other"))
        case .fileExtension:
            let ext = node.fileExtension
            return (0, ext.isEmpty ? "No Extension" : ext.uppercased())
        case .tags:
            return (0, node.tags.first ?? "No Tags")
        case .size:
            return sizeGroup(node.size, isDirectory: node.isDirectory)
        case .dateModified:
            return dateGroup(node.modificationDate)
        case .dateCreated:
            return dateGroup(node.creationDate)
        case .dateAdded:
            return dateGroup(node.dateAdded)
        case .dateLastOpened:
            return dateGroup(node.lastOpenedDate)
        case .location:
            let folder = node.url.deletingLastPathComponent()
            return (0, folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)
        }
    }

    private static func sizeGroup(_ size: Int64?, isDirectory: Bool) -> (Int, String) {
        if isDirectory { return (0, "Folders") }
        guard let size else { return (1, "Unknown Size") }
        if size == 0 { return (2, "Zero KB") }
        if size < 1_000_000 { return (3, "Under 1 MB") }
        if size < 100_000_000 { return (4, "1 MB \u{2013} 100 MB") }
        if size < 1_000_000_000 { return (5, "100 MB \u{2013} 1 GB") }
        return (6, "Over 1 GB")
    }

    private static func dateGroup(_ date: Date?) -> (Int, String) {
        guard let date else { return (5, "No Date") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return (0, "Today") }
        if calendar.isDateInYesterday(date) { return (1, "Yesterday") }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return (2, "Previous 7 Days")
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) { return (3, "Earlier This Month") }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) { return (4, "Earlier This Year") }
        return (5, "Older")
    }
}
