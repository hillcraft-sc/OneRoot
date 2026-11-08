#if os(Linux)
import Foundation
import Glibc
import CLinuxSupport

/// Linux's copy engine (the Mac's is `FileCopier`): copies a file or
/// folder with progress, Pause, and Cancel, keeping what a copy should
/// keep — permissions, modification and access dates, symbolic links as
/// links, and (with `includeMetadata`) `user.*` extended attributes such as
/// tags. The data goes through `copy_file_range`, so the kernel copies it
/// (or shares the blocks, on btrfs and XFS), falling back to plain reads
/// and writes across file systems that don't support it. A cancelled copy
/// leaves nothing behind.
enum LinuxFileCopier {
    private static let chunk = 8 * 1024 * 1024

    static func copy(
        _ source: URL,
        to destination: URL,
        includeMetadata: Bool,
        cancellation: CancellationFlag,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        // Never into (or over) something already there — and so never
        // removing it on the way out.
        var existing = stat()
        if lstat(destination.path, &existing) == 0 {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        var copied: Int64 = 0
        do {
            try copyItem(source.path, destination.path, includeMetadata: includeMetadata, cancellation: cancellation) { bytes in
                copied += bytes
                onProgress(copied)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func copyItem(
        _ source: String,
        _ destination: String,
        includeMetadata: Bool,
        cancellation: CancellationFlag,
        onBytes: (Int64) -> Void
    ) throws {
        if cancellation.isCancelled { throw CancellationError() }
        var info = stat()
        guard lstat(source, &info) == 0 else { throw posixError(source) }
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: source)
            guard symlink(target, destination) == 0 else { throw posixError(destination) }
        case S_IFDIR:
            guard mkdir(destination, 0o700) == 0 else { throw posixError(destination) }
            for name in try FileManager.default.contentsOfDirectory(atPath: source) {
                try copyItem(source + "/" + name, destination + "/" + name, includeMetadata: includeMetadata, cancellation: cancellation, onBytes: onBytes)
            }
            // After the contents, so adding them doesn't change the date.
            try finish(destination, like: info, from: source, includeMetadata: includeMetadata)
        case S_IFREG:
            try copyFile(source, destination, info: info, includeMetadata: includeMetadata, cancellation: cancellation, onBytes: onBytes)
        default:
            break // sockets, devices, pipes: not copied, as Finder doesn't
        }
    }

    /// Test-only: ONEROOT_TEST_COPY_DELAY_MS pauses that long before each copy
    /// step, so the UI harness (Scripts/linux-ui-check.sh) can hold a real copy
    /// open to press Pause/Cancel. Unset (or 0) in normal use; progress is still real.
    private static let testDelayMicroseconds: UInt32? = {
        guard let text = ProcessInfo.processInfo.environment["ONEROOT_TEST_COPY_DELAY_MS"],
              let ms = UInt32(text), ms > 0 else { return nil }
        return ms * 1000
    }()

    private static func copyFile(
        _ source: String,
        _ destination: String,
        info: stat,
        includeMetadata: Bool,
        cancellation: CancellationFlag,
        onBytes: (Int64) -> Void
    ) throws {
        let input = open(source, O_RDONLY | O_CLOEXEC)
        guard input >= 0 else { throw posixError(source) }
        defer { close(input) }
        let output = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw posixError(destination) }
        var closed = false
        defer { if !closed { close(output) } }

        var useKernelCopy = true
        var buffer: [UInt8] = []
        while true {
            if let pause = testDelayMicroseconds { usleep(pause) }
            if cancellation.isCancelled { throw CancellationError() }
            if cancellation.isPaused { cancellation.waitWhilePaused() }
            var count = -1
            if useKernelCopy {
                count = oneroot_copy_file_range(input, output, chunk)
                if count < 0, [EXDEV, ENOSYS, EINVAL, EOPNOTSUPP, EBADF, EPERM].contains(errno) {
                    useKernelCopy = false // fall back below
                    continue
                }
            } else {
                if buffer.isEmpty { buffer = [UInt8](repeating: 0, count: 1024 * 1024) }
                count = buffer.withUnsafeMutableBytes { read(input, $0.baseAddress, $0.count) }
                if count > 0 {
                    var written = 0
                    while written < count {
                        let result = buffer.withUnsafeBytes { write(output, $0.baseAddress! + written, count - written) }
                        if result < 0 {
                            if errno == EINTR { continue }
                            throw posixError(destination)
                        }
                        written += result
                    }
                }
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError(destination)
            }
            if count == 0 { break }
            onBytes(Int64(count))
        }
        if includeMetadata { copyAttributes(from: source, to: output) }
        fchmod(output, info.st_mode & 0o7777)
        var times = [info.st_atim, info.st_mtim]
        futimens(output, &times)
        closed = true
        guard close(output) == 0 else { throw posixError(destination) }
    }

    /// A folder's permissions, dates, and attributes, once it's filled.
    private static func finish(_ path: String, like info: stat, from source: String, includeMetadata: Bool) throws {
        if includeMetadata {
            for name in ExtendedAttributes.names(of: source) where name.hasPrefix("user.") {
                if let data = ExtendedAttributes.data(name, of: source) {
                    try? ExtendedAttributes.set(data, name, of: path)
                }
            }
        }
        chmod(path, info.st_mode & 0o7777)
        var times = [info.st_atim, info.st_mtim]
        utimensat(AT_FDCWD, path, &times, 0)
    }

    /// The `user.*` attributes (tags and the like). One the destination
    /// can't store is skipped rather than failing the copy.
    private static func copyAttributes(from source: String, to output: Int32) {
        for name in ExtendedAttributes.names(of: source) where name.hasPrefix("user.") {
            guard let data = ExtendedAttributes.data(name, of: source) else { continue }
            _ = data.withUnsafeBytes { fsetxattr(output, name, $0.baseAddress, data.count, 0) }
        }
    }

    /// Whether `url`'s file system keeps `user.*` attributes — so a copy
    /// there needn't skip them (NFS and SMB shares mostly don't).
    static func storesMetadataNatively(_ url: URL) -> Bool {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        guard let type = MountTable.current()?.entry(containing: probe.resolvingSymlinksInPath().path)?.type else { return false }
        return !LinuxVolumeRules.networkTypes.contains(type) && !["vfat", "msdos", "exfat", "ntfs", "ntfs3", "fuseblk"].contains(type)
    }

    /// A failed system call as a Cocoa error with the system's own words
    /// ("Permission denied", "No space left on device") — Foundation on Linux
    /// has no friendly text for the generic write error.
    private static func posixError(_ path: String) -> Error {
        let code = errno
        let cocoaCode: CocoaError.Code
        switch code {
        case EACCES, EPERM: cocoaCode = .fileWriteNoPermission
        case ENOSPC, EDQUOT: cocoaCode = .fileWriteOutOfSpace
        case EROFS: cocoaCode = .fileWriteVolumeReadOnly
        case ENOENT: cocoaCode = .fileNoSuchFile
        default: cocoaCode = .fileWriteUnknown
        }
        return CocoaError(cocoaCode, userInfo: [
            NSFilePathErrorKey: path,
            NSLocalizedDescriptionKey: String(cString: strerror(code)),
            NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO),
        ])
    }
}
#endif
