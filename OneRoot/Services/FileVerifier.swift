import Foundation
#if canImport(Glibc)
import Glibc
#endif

enum FileVerificationError: LocalizedError {
    case contentsDiffer(String)
    case structureDiffers(String)
    case unreadable(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .contentsDiffer(let name):
            return "The copy of \u{201C}\(name)\u{201D} doesn\u{2019}t match the original, so it was removed. Try again, and check the disk if it happens again."
        case .structureDiffers(let name):
            return "The copy of \u{201C}\(name)\u{201D} is missing items or has extra ones, so it was removed."
        case .unreadable(let name, let underlying):
            return "Couldn\u{2019}t read \u{201C}\(name)\u{201D} to check the copy: \(underlying.localizedDescription)"
        }
    }
}

/// Settings ▸ General ▸ Verify copies: checks a finished copy against its
/// original, byte for byte, reading both with the file cache bypassed
/// (`F_NOCACHE`) so the check reads what actually reached the disk rather
/// than what's still in memory from writing it. Folders are checked
/// item by item; symbolic links by where they point.
enum FileVerifier {
    static let enabledKey = "com.oneroot.fileOperations.verifyCopies"

    private static let chunkSize = 1 << 20

    /// Throws `FileVerificationError` when `copy` doesn't match `original`,
    /// `CancellationError` when cancelled. `onProgress` gets bytes checked
    /// so far.
    static func verify(
        _ original: URL,
        matches copy: URL,
        cancellation: CancellationFlag,
        onProgress: (Int64) -> Void = { _ in }
    ) throws {
        var checked: Int64 = 0
        try verifyItem(original, copy, name: original.lastPathComponent, cancellation: cancellation) { bytes in
            checked += bytes
            onProgress(checked)
        }
    }

    private static func verifyItem(
        _ original: URL,
        _ copy: URL,
        name: String,
        cancellation: CancellationFlag,
        onBytes: (Int64) -> Void
    ) throws {
        if cancellation.isCancelled { throw CancellationError() }
        let fileManager = FileManager.default
        let originalType: FileAttributeType
        let copyType: FileAttributeType
        do {
            originalType = try fileManager.attributesOfItem(atPath: original.path)[.type] as? FileAttributeType ?? .typeUnknown
            copyType = try fileManager.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType ?? .typeUnknown
        } catch {
            throw FileVerificationError.unreadable(name, underlying: error)
        }
        guard originalType == copyType else { throw FileVerificationError.structureDiffers(name) }

        switch originalType {
        case .typeDirectory:
            let originalNames: [String]
            let copyNames: [String]
            do {
                originalNames = try fileManager.contentsOfDirectory(atPath: original.path).sorted()
                copyNames = try fileManager.contentsOfDirectory(atPath: copy.path).sorted()
            } catch {
                throw FileVerificationError.unreadable(name, underlying: error)
            }
            guard originalNames == copyNames else { throw FileVerificationError.structureDiffers(name) }
            for child in originalNames {
                try verifyItem(
                    original.appendingPathComponent(child),
                    copy.appendingPathComponent(child),
                    name: name,
                    cancellation: cancellation,
                    onBytes: onBytes
                )
            }
        case .typeSymbolicLink:
            let originalTarget = try? fileManager.destinationOfSymbolicLink(atPath: original.path)
            let copyTarget = try? fileManager.destinationOfSymbolicLink(atPath: copy.path)
            guard originalTarget == copyTarget else { throw FileVerificationError.contentsDiffer(name) }
        case .typeRegular:
            try compareContents(original, copy, name: name, cancellation: cancellation, onBytes: onBytes)
        default:
            break // sockets, devices: nothing to compare
        }
    }

    private static func compareContents(
        _ original: URL,
        _ copy: URL,
        name: String,
        cancellation: CancellationFlag,
        onBytes: (Int64) -> Void
    ) throws {
        let a = open(original.path, O_RDONLY)
        guard a >= 0 else { throw FileVerificationError.unreadable(name, underlying: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        defer { close(a) }
        let b = open(copy.path, O_RDONLY)
        guard b >= 0 else { throw FileVerificationError.unreadable(name, underlying: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        defer { close(b) }
        Self.bypassCache(a)
        Self.bypassCache(b)

        var bufferA = [UInt8](repeating: 0, count: chunkSize)
        var bufferB = [UInt8](repeating: 0, count: chunkSize)
        while true {
            if cancellation.isCancelled { throw CancellationError() }
            if cancellation.isPaused { cancellation.waitWhilePaused() }
            let countA = try readFully(a, into: &bufferA, name: name)
            let countB = try readFully(b, into: &bufferB, name: name)
            guard countA == countB else { throw FileVerificationError.contentsDiffer(name) }
            if countA == 0 { return }
            let same = bufferA.withUnsafeBytes { pa in
                bufferB.withUnsafeBytes { pb in
                    guard let left = pa.baseAddress, let right = pb.baseAddress else { return false }
                    return memcmp(left, right, countA) == 0
                }
            }
            guard same else { throw FileVerificationError.contentsDiffer(name) }
            onBytes(Int64(countA))
        }
    }

    /// Reads from the disk rather than the cache: `F_NOCACHE` on macOS;
    /// on Linux, dropping what's cached for the file before reading it.
    private static func bypassCache(_ fd: Int32) {
        #if os(Linux)
        _ = posix_fadvise(fd, 0, 0, Int32(POSIX_FADV_DONTNEED))
        #else
        _ = fcntl(fd, F_NOCACHE, 1)
        #endif
    }

    /// Fills `buffer` as far as the file allows; 0 at the end.
    private static func readFully(_ fd: Int32, into buffer: inout [UInt8], name: String) throws -> Int {
        var total = 0
        while total < buffer.count {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return read(fd, base.advanced(by: total), raw.count - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw FileVerificationError.unreadable(name, underlying: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
            }
            if count == 0 { break }
            total += count
        }
        return total
    }
}
