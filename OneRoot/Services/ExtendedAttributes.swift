import Foundation
#if canImport(Glibc)
import Glibc
#if canImport(CLinuxSupport)
import CLinuxSupport
#endif
#elseif canImport(Darwin)
import Darwin
#endif

/// Reads and writes a file's extended attributes — on Linux, the `user.*`
/// ones file systems like ext4, btrfs and XFS keep (where tags live).
/// Symbolic links themselves aren't touched: Linux allows no `user.*`
/// attributes on them.
enum ExtendedAttributes {
    static func data(_ name: String, of path: String) -> Data? {
        #if os(Linux)
        let size = getxattr(path, name, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size)
        guard read >= 0 else { return nil }
        return Data(buffer[0..<read])
        #else
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, 0)
        guard read >= 0 else { return nil }
        return Data(buffer[0..<read])
        #endif
    }

    static func set(_ data: Data, _ name: String, of path: String) throws {
        let result = data.withUnsafeBytes { bytes -> Int32 in
            #if os(Linux)
            return setxattr(path, name, bytes.baseAddress, data.count, 0)
            #else
            return setxattr(path, name, bytes.baseAddress, data.count, 0, 0)
            #endif
        }
        guard result == 0 else { throw error(path) }
    }

    static func remove(_ name: String, of path: String) throws {
        #if os(Linux)
        let result = removexattr(path, name)
        #else
        let result = removexattr(path, name, 0)
        #endif
        guard result == 0 || errno == ENODATA || errno == ENOATTR else { throw error(path) }
    }

    /// The names a file has (`user.xdg.tags`, …).
    static func names(of path: String) -> [String] {
        #if os(Linux)
        let size = listxattr(path, nil, 0)
        #else
        let size = listxattr(path, nil, 0, 0)
        #endif
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        #if os(Linux)
        let read = listxattr(path, &buffer, size)
        #else
        let read = listxattr(path, &buffer, size, 0)
        #endif
        guard read > 0 else { return [] }
        return buffer[0..<read].split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }

    private static func error(_ path: String) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [
            NSFilePathErrorKey: path,
            NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO),
        ])
    }
}

#if os(Linux)
private let ENOATTR = ENODATA
#endif

/// Tags as the Linux desktops keep them: the `user.xdg.tags` extended
/// attribute, names separated by commas — what KDE's Dolphin (and Baloo's
/// search) read and write, so tags set in either app show in the other.
enum XDGTags {
    static let attribute = "user.xdg.tags"

    static func tags(of url: URL) -> [String] {
        guard let data = ExtendedAttributes.data(attribute, of: url.path) else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func setTags(_ tags: [String], on url: URL) throws {
        let cleaned = tags.map { $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if cleaned.isEmpty {
            try ExtendedAttributes.remove(attribute, of: url.path)
        } else {
            try ExtendedAttributes.set(Data(cleaned.joined(separator: ",").utf8), attribute, of: url.path)
        }
    }

    static func parse(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
