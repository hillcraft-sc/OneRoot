#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // Linux: swift-crypto, the same API
#endif
import Foundation

struct DuplicateFile: Identifiable, Hashable, Sendable {
    let url: URL
    let modified: Date?
    var id: URL { url }
}

/// Files with identical contents.
struct DuplicateGroup: Identifiable, Sendable, Equatable {
    let id = UUID()
    let size: Int64
    /// Oldest first.
    var files: [DuplicateFile]

    /// Space freed by keeping one.
    var reclaimable: Int64 { size * Int64(max(files.count - 1, 0)) }

    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.id == rhs.id && lhs.files == rhs.files
    }
}

/// #67: finds files with identical contents under one or more folders.
/// Files are grouped by size first (only same-size files can match), then
/// by a fingerprint of their first 4 KB, and only what still matches is
/// read in full and compared by SHA-256 — so most files are never read.
/// Skips empty files, symbolic links, anything inside packages (an app's
/// insides aren't yours to tidy), and second links to the same file (a
/// hard link takes no extra space). Cancellable throughout.
struct DuplicateFinder {
    enum Phase: Equatable, Sendable {
        case scanning(files: Int)
        case comparing(done: Int, of: Int)
    }

    func find(
        in roots: [URL],
        includeHidden: Bool,
        cancellation: CancellationFlag,
        onProgress: @escaping @Sendable (Phase) -> Void = { _ in }
    ) async throws -> [DuplicateGroup] {
        try await Task.detached(priority: .userInitiated) {
            // 1. Every file, by size.
            var bySize: [Int64: [DuplicateFile]] = [:]
            var seenFiles: Set<String> = [] // volume + inode: hard links and overlapping roots
            var scanned = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
            var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !includeHidden { options.insert(.skipsHiddenFiles) }
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options, errorHandler: { _, _ in true }) else { continue }
                while let url = enumerator.nextObject() as? URL {
                    if cancellation.isCancelled { throw CancellationError() }
                    guard let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true, values.isSymbolicLink != true,
                          let size = values.fileSize, size > 0 else { continue }
                    if let identity = Self.identity(of: url) {
                        guard seenFiles.insert(identity).inserted else { continue }
                    }
                    bySize[Int64(size), default: []].append(DuplicateFile(url: url, modified: values.contentModificationDate))
                    scanned += 1
                    if scanned % 500 == 0 { onProgress(.scanning(files: scanned)) }
                }
            }
            onProgress(.scanning(files: scanned))

            // 2. Same size → same first 4 KB → same SHA-256.
            let candidates = bySize.filter { $0.value.count > 1 }
            let total = candidates.values.reduce(0) { $0 + $1.count }
            var done = 0
            var groups: [DuplicateGroup] = []
            for (size, files) in candidates {
                if cancellation.isCancelled { throw CancellationError() }
                let byPrefix = Dictionary(grouping: files) { Self.digest(of: $0.url, limit: 4096, cancellation: cancellation) }
                for (prefix, prefixMatches) in byPrefix where prefix != nil && prefixMatches.count > 1 {
                    let byContents: [String?: [DuplicateFile]]
                    if size <= 4096 {
                        byContents = [prefix: prefixMatches] // already read whole
                    } else {
                        byContents = Dictionary(grouping: prefixMatches) { Self.digest(of: $0.url, limit: nil, cancellation: cancellation) }
                    }
                    for (digest, matches) in byContents where digest != nil && matches.count > 1 {
                        let sorted = matches.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
                        groups.append(DuplicateGroup(size: size, files: sorted))
                    }
                }
                done += files.count
                onProgress(.comparing(done: done, of: total))
            }
            if cancellation.isCancelled { throw CancellationError() }
            return groups.sorted {
                $0.reclaimable != $1.reclaimable ? $0.reclaimable > $1.reclaimable : $0.files[0].url.path < $1.files[0].url.path
            }
        }.value
    }

    /// Device and inode: the same for every hard link to one file.
    private static func identity(of url: URL) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return "\(info.st_dev)-\(info.st_ino)"
    }

    /// SHA-256 of the first `limit` bytes (all of it when `nil`); `nil`
    /// when the file can't be read — it's then left out rather than
    /// guessed at.
    static func digest(of url: URL, limit: Int?, cancellation: CancellationFlag) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if cancellation.isCancelled { return nil }
            let chunk = min(remaining, 1 << 20)
            let data: Data?
            do {
                data = try handle.read(upToCount: chunk)
            } catch {
                return nil
            }
            // `nil` or empty: the end of the file.
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
