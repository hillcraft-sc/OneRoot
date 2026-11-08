import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The kernel's list of mounted file systems (Linux: /proc/self/mounts):
/// where each is mounted and what type it is. Read fresh each time — mounts
/// come and go.
struct MountTable: Equatable {
    struct Entry: Equatable {
        let device: String
        let mountPoint: String
        let type: String
    }

    let entries: [Entry]

    /// Parses the /proc/self/mounts format: "device mountpoint type options
    /// dump pass", with spaces (and other odd characters) in paths written
    /// as octal escapes like \040.
    init(parsing table: String) {
        entries = table.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count >= 3 else { return nil }
            return Entry(
                device: Self.unescape(String(fields[0])),
                mountPoint: Self.unescape(String(fields[1])),
                type: String(fields[2])
            )
        }
    }

    /// This machine's, or `nil` where there's no /proc (macOS).
    static func current() -> MountTable? {
        readWholeFile("/proc/self/mounts").map(MountTable.init(parsing:))
    }

    /// Reads a /proc file to the end. They report a size of 0, and
    /// Foundation's readers stop after the first 4 KB — dropping every
    /// mount listed after that, newly plugged drives included.
    static func readWholeFile(_ path: String) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            bytes.append(contentsOf: chunk[0..<count])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The mount `path` is on: the longest mount point that contains it.
    func entry(containing path: String) -> Entry? {
        var best: Entry?
        for entry in entries {
            let point = entry.mountPoint
            let contains = point == "/" || path == point || path.hasPrefix(point.hasSuffix("/") ? point : point + "/")
            if contains, point.count >= (best?.mountPoint.count ?? -1) {
                best = entry
            }
        }
        return best
    }

    /// "\040" → " ", and the like.
    static func unescape(_ field: String) -> String {
        guard field.contains("\\") else { return field }
        var bytes: [UInt8] = []
        var scalars = Array(field.utf8)[...]
        while let byte = scalars.popFirst() {
            if byte == UInt8(ascii: "\\"), scalars.count >= 3,
               let value = UInt8(String(decoding: scalars.prefix(3), as: UTF8.self), radix: 8) {
                bytes.append(value)
                scalars = scalars.dropFirst(3)
            } else {
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
