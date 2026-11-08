import Foundation

/// What the Inspector can read about one item with Foundation alone: the
/// Linux counterpart of the Mac's `ItemDetailsService`. Every value is
/// optional — nothing is guessed — and reading happens off the main thread
/// (a network mount can take a moment).
struct ItemInfo: Equatable, Sendable {
    var size: Int64?
    var sizeOnDisk: Int64?
    /// Birth time, where the filesystem records it (nil otherwise — never guessed).
    var created: Date?
    var modified: Date?
    var accessed: Date?
    var owner: String?
    var group: String?
    var permissions: Int?
    var linkDestination: String?
    /// Folders only: items directly inside (hidden ones not counted).
    var itemCount: Int?
    /// Plain text to preview, if the file is text.
    var textPreview: String?

    enum ReadError: Error, Equatable {
        case permissionDenied
        case notFound
        case other(String)
    }

    static let previewBytes = 4096

    /// Reads `url`. Throws a `ReadError` so the Inspector can say why it has
    /// nothing, instead of showing an empty panel.
    static func read(_ url: URL, isDirectory: Bool, wantsText: Bool, textBytes: Int = previewBytes) throws -> ItemInfo {
        let manager = FileManager.default
        var info = ItemInfo()
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            throw map(error)
        }
        info.size = (attributes[.size] as? NSNumber)?.int64Value
        info.modified = attributes[.modificationDate] as? Date
        info.created = attributes[.creationDate] as? Date
        info.owner = attributes[.ownerAccountName] as? String
        info.group = attributes[.groupOwnerAccountName] as? String
        info.permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue

        var status = stat()
        if stat(url.path, &status) == 0 {
            info.sizeOnDisk = Int64(status.st_blocks) * 512
            info.accessed = Date(timeIntervalSince1970: TimeInterval(status.st_atim.tv_sec))
        }
        if (attributes[.type] as? FileAttributeType) == .typeSymbolicLink {
            info.linkDestination = try? manager.destinationOfSymbolicLink(atPath: url.path)
        }
        if isDirectory {
            do {
                let names = try manager.contentsOfDirectory(atPath: url.path)
                info.itemCount = names.filter { !$0.hasPrefix(".") }.count
            } catch {
                throw map(error)
            }
            info.size = nil
        } else if wantsText {
            info.textPreview = text(at: url, bytes: textBytes)
        }
        return info
    }

    /// The start of a text file, or nil for anything that isn't text (a NUL
    /// byte or invalid UTF-8 within the first chunk).
    static func text(at url: URL, bytes: Int = previewBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes), !data.isEmpty, !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        // The chunk may end inside a multi-byte character: drop up to 3 bytes.
        for drop in 1...3 where data.count > drop {
            if let text = String(data: data.dropLast(drop), encoding: .utf8) { return text }
        }
        return nil
    }

    /// "rwxr-xr-x (755)"
    static func permissionText(_ mode: Int) -> String {
        let symbols = ["r", "w", "x"]
        var text = ""
        for shift in stride(from: 6, through: 0, by: -3) {
            let bits = (mode >> shift) & 0o7
            for (index, symbol) in symbols.enumerated() {
                text += bits & (4 >> index) != 0 ? symbol : "-"
            }
        }
        return "\(text) (\(String(mode & 0o777, radix: 8)))"
    }

    private static func map(_ error: Error) -> ReadError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError: return .permissionDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .notFound
            default: break
            }
        }
        if let posix = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            if posix.code == Int(EACCES) || posix.code == Int(EPERM) { return .permissionDenied }
            if posix.code == Int(ENOENT) { return .notFound }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            if nsError.code == Int(EACCES) || nsError.code == Int(EPERM) { return .permissionDenied }
            if nsError.code == Int(ENOENT) { return .notFound }
        }
        return .other(error.localizedDescription)
    }
}
