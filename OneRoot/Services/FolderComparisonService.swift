import Foundation

/// How an item in one Dual Pane folder compares with the item of the same
/// name in the other, from this side's point of view.
enum ComparisonStatus: Hashable, Sendable {
    /// Same on both sides (for a folder: everything inside is).
    case same
    /// Not in the other folder.
    case onlyHere
    /// This side has the newer version (for a folder: only this side has
    /// newer or extra things inside).
    case newerHere
    /// The other side has the newer version.
    case olderHere
    /// Changed on both sides, same date but different size, or a file on
    /// one side and a folder on the other — no single direction to copy.
    case differs

    /// The other side's view of the same item.
    var mirrored: ComparisonStatus {
        switch self {
        case .same: return .same
        case .onlyHere: return .onlyHere // only ever set on the side that has it
        case .newerHere: return .olderHere
        case .olderHere: return .newerHere
        case .differs: return .differs
        }
    }
}

/// The result of comparing two folders, keyed by item name on each side.
struct FolderComparison: Equatable, Sendable {
    var left: [String: ComparisonStatus] = [:]
    var right: [String: ComparisonStatus] = [:]
    /// Folders inside that couldn't be read; their items count as `differs`.
    var unreadableCount = 0

    func statuses(onLeft: Bool) -> [String: ComparisonStatus] { onLeft ? left : right }

    /// How many items on one side have each status.
    func count(_ status: ComparisonStatus, onLeft: Bool) -> Int {
        statuses(onLeft: onLeft).values.filter { $0 == status }.count
    }

    /// Whether every item matches.
    var isIdentical: Bool {
        left.values.allSatisfy { $0 == .same } && right.values.allSatisfy { $0 == .same }
    }
}

/// Compares two folders, subfolders included, by name, size, and
/// modification date (within a second — copies to other volumes often
/// round timestamps). No contents are read. Finder's `.DS_Store` files are
/// ignored; packages (apps and the like) are compared like folders but
/// shown as one item. Symbolic links are compared as links, not followed.
struct FolderComparisonService {
    func compare(
        _ left: URL,
        _ right: URL,
        cancellation: CancellationFlag,
        onProgress: @escaping @Sendable (Int) -> Void = { _ in }
    ) async throws -> FolderComparison {
        try await Task.detached(priority: .userInitiated) {
            var walker = Walker(cancellation: cancellation, onProgress: onProgress)
            let result = try walker.compareTop(left, right)
            return result
        }.value
    }

    /// When syncing one pane into the other: merge folders, replace a
    /// file only with a newer one (the old one goes to the Trash), and skip
    /// everything else — nothing newer on the receiving side is ever
    /// overwritten, and a file never replaces a folder or the reverse.
    static func syncAnswer(for request: FileConflictRequest) -> FileConflictAnswer {
        var answers: [URL: FileConflictResolution] = [:]
        for conflict in request.conflicts {
            if conflict.canMerge {
                answers[conflict.source] = .merge
            } else if conflict.incoming.isDirectory == conflict.current.isDirectory, conflict.newer == .incoming {
                answers[conflict.source] = .replace
            } else {
                answers[conflict.source] = .skip
            }
        }
        return .resolve(answers)
    }

    /// The items on one side that Copy to the other side would send:
    /// what's only here, newer here, or differs in a folder (the merge
    /// copies only the newer and missing things inside). A file that
    /// differs without being newer isn't copied.
    static func itemsToCopy(from statuses: [String: ComparisonStatus], in folder: URL, isDirectory: (URL) -> Bool) -> [URL] {
        statuses.compactMap { name, status -> URL? in
            let url = folder.appendingPathComponent(name)
            switch status {
            case .onlyHere, .newerHere: return url
            case .differs: return isDirectory(url) ? url : nil
            case .same, .olderHere: return nil
            }
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

/// The recursive walk. Tracks, for a pair of folders, whether either side
/// is "ahead" (has something newer or extra), or the two conflict.
private struct Walker {
    let cancellation: CancellationFlag
    let onProgress: @Sendable (Int) -> Void
    var scanned = 0
    var unreadable = 0

    init(cancellation: CancellationFlag, onProgress: @escaping @Sendable (Int) -> Void) {
        self.cancellation = cancellation
        self.onProgress = onProgress
    }

    struct Entry {
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let size: Int64
        let modified: Date?
    }

    struct Difference {
        var leftAhead = false
        var rightAhead = false
        var conflict = false

        mutating func formUnion(_ other: Difference) {
            leftAhead = leftAhead || other.leftAhead
            rightAhead = rightAhead || other.rightAhead
            conflict = conflict || other.conflict
        }

        /// The left side's status for an item with this difference.
        var leftStatus: ComparisonStatus {
            if conflict || (leftAhead && rightAhead) { return .differs }
            if leftAhead { return .newerHere }
            if rightAhead { return .olderHere }
            return .same
        }
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]

    mutating func compareTop(_ left: URL, _ right: URL) throws -> FolderComparison {
        guard let leftEntries = try listing(left), let rightEntries = try listing(right) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var result = FolderComparison()
        for name in Set(leftEntries.keys).union(rightEntries.keys) {
            switch (leftEntries[name], rightEntries[name]) {
            case (.some, nil):
                result.left[name] = .onlyHere
            case (nil, .some):
                result.right[name] = .onlyHere
            case let (l?, r?):
                let status = try difference(left.appendingPathComponent(name), l, right.appendingPathComponent(name), r).leftStatus
                result.left[name] = status
                result.right[name] = status.mirrored
            case (nil, nil):
                break
            }
        }
        result.unreadableCount = unreadable
        return result
    }

    private mutating func difference(_ leftURL: URL, _ l: Entry, _ rightURL: URL, _ r: Entry) throws -> Difference {
        if cancellation.isCancelled { throw CancellationError() }
        let leftIsFolder = l.isDirectory && !l.isSymbolicLink
        let rightIsFolder = r.isDirectory && !r.isSymbolicLink
        guard leftIsFolder == rightIsFolder else { return Difference(conflict: true) }
        guard leftIsFolder else { return Self.fileDifference(l, r) }

        guard let leftEntries = try listing(leftURL), let rightEntries = try listing(rightURL) else {
            return Difference(conflict: true)
        }
        var total = Difference()
        for name in Set(leftEntries.keys).union(rightEntries.keys) {
            switch (leftEntries[name], rightEntries[name]) {
            case (.some, nil): total.leftAhead = true
            case (nil, .some): total.rightAhead = true
            case let (cl?, cr?):
                total.formUnion(try difference(leftURL.appendingPathComponent(name), cl, rightURL.appendingPathComponent(name), cr))
            case (nil, nil): break
            }
        }
        return total
    }

    static func fileDifference(_ l: Entry, _ r: Entry) -> Difference {
        if let leftDate = l.modified, let rightDate = r.modified {
            let delta = leftDate.timeIntervalSince(rightDate)
            if delta > 1 { return Difference(leftAhead: true) }
            if delta < -1 { return Difference(rightAhead: true) }
        }
        return l.size == r.size ? Difference() : Difference(conflict: true)
    }

    /// A folder's entries by name, or `nil` when it can't be read.
    private mutating func listing(_ folder: URL) throws -> [String: Entry]? {
        if cancellation.isCancelled { throw CancellationError() }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            unreadable += 1
            return nil
        }
        var entries: [String: Entry] = [:]
        for name in names where name != ".DS_Store" {
            let values = try? folder.appendingPathComponent(name).resourceValues(forKeys: Set(Self.keys))
            entries[name] = Entry(
                isDirectory: values?.isDirectory ?? false,
                isSymbolicLink: values?.isSymbolicLink ?? false,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate
            )
        }
        scanned += entries.count
        onProgress(scanned)
        return entries
    }
}
