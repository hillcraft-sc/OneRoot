import Foundation

/// UI-agnostic recursive folder sizes for the Size column (see
/// `FileListViewModel.folderSizes`). Counts every file inside, hidden ones
/// and package contents included — what the folder actually holds, the way
/// Finder's "Calculate all sizes" does — using each file's logical size so
/// folder and file rows add up consistently.
struct FolderSizeService {
    /// Total bytes inside `folder`. Unreadable items along the way are
    /// skipped rather than failing the whole folder. Throws
    /// `CancellationError` promptly if the calling task is cancelled — a big
    /// folder can take a while, and navigating away shouldn't have to wait.
    func size(of folder: URL) async throws -> Int64 {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Self.walk(folder, cancellation: cancellation)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func walk(_ folder: URL, cancellation: CancellationFlag) throws -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited % 500 == 0, cancellation.isCancelled { throw CancellationError() }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        if cancellation.isCancelled { throw CancellationError() }
        return total
    }
}

/// Folder sizes already worked out, app-wide, so coming back to a folder
/// shows its subfolders' sizes immediately while they're re-checked in the
/// background (they may have changed while nothing was watching them).
@MainActor
final class FolderSizeCache {
    static let shared = FolderSizeCache()

    private var sizes: [String: Int64] = [:]
    private let limit = 5_000

    func size(of folder: URL) -> Int64? {
        sizes[folder.standardizedFileURL.path]
    }

    func store(_ size: Int64, for folder: URL) {
        if sizes.count >= limit { sizes.removeAll(keepingCapacity: true) }
        sizes[folder.standardizedFileURL.path] = size
    }

    /// Forgets every cached folder at or above one of `changedPaths` — a
    /// file changing anywhere inside a folder changes that folder's size.
    /// Returns the folders forgotten.
    @discardableResult
    func invalidate(containing changedPaths: Set<String>) -> Set<String> {
        let stale = Set(sizes.keys.filter { folder in
            changedPaths.contains { $0 == folder || $0.hasPrefix(folder + "/") }
        })
        for folder in stale { sizes.removeValue(forKey: folder) }
        return stale
    }
}
