import Foundation

enum FileConflictResolution: Sendable {
    case replace
    case keepBoth
    case skip
    /// Folder into folder only: the incoming folder's contents go into the
    /// existing one, asking again about anything inside that collides.
    case merge
}

/// One name collision found before a copy/move starts: an item being
/// copied/moved whose name is already taken in the destination.
struct FileConflictItem: Identifiable, Sendable, Equatable {
    /// What's being copied/moved.
    let source: URL
    /// What's already there under that name.
    let existing: URL
    let incoming: Metadata
    let current: Metadata

    var id: URL { source }
    var name: String { source.lastPathComponent }

    /// Both sides are ordinary folders, so Merge is on offer.
    var canMerge: Bool { incoming.isMergeableFolder && current.isMergeableFolder }

    /// What the comparison in the conflict dialog shows. Sizes are for
    /// files only — a folder's would mean a recursive scan before the
    /// dialog could even appear.
    struct Metadata: Sendable, Equatable {
        var isDirectory: Bool
        /// An app, bundle, or other package — a folder on disk that's one
        /// document to the user, so never merged.
        var isPackage = false
        var modified: Date?
        var size: Int64?

        var isMergeableFolder: Bool { isDirectory && !isPackage }

        static func read(_ url: URL) -> Metadata {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey])
            let isDirectory = values?.isDirectory ?? false
            return Metadata(
                isDirectory: isDirectory,
                isPackage: Platform.hasPackages && (values?.isPackage ?? false),
                modified: values?.contentModificationDate,
                size: isDirectory ? nil : values?.fileSize.map(Int64.init)
            )
        }
    }

    enum Side: Sendable { case incoming, existing }

    /// The side modified later, when the two differ by more than a second
    /// (copies across volumes often round timestamps).
    var newer: Side? {
        guard let incomingDate = incoming.modified, let currentDate = current.modified else { return nil }
        let difference = incomingDate.timeIntervalSince(currentDate)
        if difference > 1 { return .incoming }
        if difference < -1 { return .existing }
        return nil
    }

    init(source: URL, existing: URL, incoming: Metadata, current: Metadata) {
        self.source = source
        self.existing = existing
        self.incoming = incoming
        self.current = current
    }

    /// Reads both sides' metadata from disk.
    init(source: URL, existing: URL) {
        self.init(source: source, existing: existing, incoming: .read(source), current: .read(existing))
    }
}

/// Every collision in one copy/move, asked about together before anything
/// is copied — or, for a collision that only appears once the operation is
/// under way, on its own.
struct FileConflictRequest: Identifiable, Sendable {
    let id = UUID()
    let conflicts: [FileConflictItem]
    /// All the items in the operation, conflicting or not.
    let itemCount: Int
    let destination: URL
    let isMove: Bool
}

/// The user's answer to a `FileConflictRequest`.
enum FileConflictAnswer: Sendable, Equatable {
    /// Stop: copy/move nothing more.
    case cancel
    /// A choice per conflict, by source URL. A conflict missing from the
    /// map is skipped — the safe default.
    case resolve([URL: FileConflictResolution])

    /// The same choice for every conflict in `conflicts`.
    static func all(_ resolution: FileConflictResolution, for conflicts: [FileConflictItem]) -> FileConflictAnswer {
        .resolve(Dictionary(uniqueKeysWithValues: conflicts.map { ($0.source, resolution) }))
    }
}
