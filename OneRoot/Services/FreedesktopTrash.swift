import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The Trash on Linux, as the freedesktop.org Trash specification defines
/// it — the one GNOME Files, Dolphin, and every other desktop use, so items
/// trashed here show up in theirs, and theirs here, with Put Back working
/// both ways.
///
/// Each Trash folder has `files/` (the items themselves) and `info/` (one
/// `name.trashinfo` per item, holding where it came from and when). Items
/// in the home folder's file system go to the home Trash
/// (`$XDG_DATA_HOME/Trash`, normally ~/.local/share/Trash); items on another
/// drive go to a Trash at that drive's top — `.Trash/$uid` if the drive has
/// a shared `.Trash` folder set up for it, otherwise `.Trash-$uid` — so
/// trashing never copies a file across drives. Where none can be made (a
/// read-only drive, say) it throws `NSFeatureUnsupportedError`, which
/// `TrashFallback` turns into the offer to delete immediately.
///
/// Plain Foundation and POSIX, so it's tested on macOS too, with every
/// location injected.
struct FreedesktopTrash {
    /// The home Trash folder (holding files/ and info/).
    var homeTrash: URL
    /// The mount point of the file system `path` is on.
    var mountPoint: (String) -> String?
    var userID: UInt32
    var now: () -> Date

    /// The real one: $XDG_DATA_HOME/Trash, the mount table, this user.
    static func system() -> FreedesktopTrash {
        let environment = ProcessInfo.processInfo.environment
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share", isDirectory: true)
        return FreedesktopTrash(
            homeTrash: dataHome.appendingPathComponent("Trash", isDirectory: true),
            mountPoint: { MountTable.current()?.entry(containing: $0)?.mountPoint },
            userID: getuid(),
            now: Date.init
        )
    }

    var homeTrashFiles: URL { homeTrash.appendingPathComponent("files", isDirectory: true) }

    /// Makes the home Trash's `files/` and `info/` if they aren't there yet
    /// (a fresh account that never trashed anything), so opening the Trash
    /// shows an empty folder instead of nothing.
    func ensureHomeTrashExists() {
        try? Self.makePrivateDirectory(homeTrashFiles)
        try? Self.makePrivateDirectory(homeTrash.appendingPathComponent("info", isDirectory: true))
    }

    // MARK: Trashing

    /// Moves `url` into the right Trash, records where it came from, and
    /// returns where it is now.
    func trash(_ url: URL) throws -> URL {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) || Self.isSymlink(path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        let (trashDirectory, topDirectory) = try trashDirectory(for: path)
        let files = trashDirectory.appendingPathComponent("files", isDirectory: true)
        let info = trashDirectory.appendingPathComponent("info", isDirectory: true)
        try Self.makePrivateDirectory(files)
        try Self.makePrivateDirectory(info)

        // Recorded relative to the drive's top in a drive's own Trash (so it
        // still works if the drive mounts somewhere else next time), and in
        // full in the home Trash.
        let recordedPath: String
        if let topDirectory {
            recordedPath = String(path.dropFirst(topDirectory.count).drop { $0 == "/" })
        } else {
            recordedPath = path
        }
        let (name, infoFile) = try reserveName(for: url.lastPathComponent, in: info, recording: recordedPath)
        let destination = files.appendingPathComponent(name)
        guard rename(path, destination.path) == 0 else {
            let error = errno
            try? FileManager.default.removeItem(at: infoFile)
            throw Self.error(errno: error, path: path)
        }
        return destination
    }

    /// The Trash for `path`, and — for a drive's own Trash — that drive's top.
    private func trashDirectory(for path: String) throws -> (URL, String?) {
        // The home Trash may not exist yet: its nearest existing folder is
        // on the same drive.
        var probe = homeTrash
        var homeTrashDevice = Self.device(of: probe.path)
        while homeTrashDevice == nil, probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
            homeTrashDevice = Self.device(of: probe.path)
        }
        guard let itemDevice = Self.device(of: (path as NSString).deletingLastPathComponent) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        if itemDevice == homeTrashDevice {
            return (homeTrash, nil)
        }
        guard let top = mountPoint(path) else {
            throw CocoaError(.featureUnsupported, userInfo: [NSFilePathErrorKey: path])
        }
        let topURL = URL(fileURLWithPath: top, isDirectory: true)
        // A shared .Trash set up by the administrator: a real folder (not a
        // link) with the sticky bit, holding one folder per user.
        let shared = topURL.appendingPathComponent(".Trash", isDirectory: true)
        var info = stat()
        if lstat(shared.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, (info.st_mode & S_ISVTX) != 0 {
            let mine = shared.appendingPathComponent(String(userID), isDirectory: true)
            if (try? Self.makePrivateDirectory(mine)) != nil {
                return (mine, top)
            }
        }
        let own = topURL.appendingPathComponent(".Trash-\(userID)", isDirectory: true)
        do {
            try Self.makePrivateDirectory(own)
        } catch {
            throw CocoaError(.featureUnsupported, userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: error])
        }
        return (own, top)
    }

    /// Claims a free name — "report.pdf", then "report.2.pdf", … — by
    /// creating its .trashinfo exclusively, so two trashings at once can't
    /// pick the same one.
    private func reserveName(for name: String, in info: URL, recording path: String) throws -> (String, URL) {
        let contents = Data("""
            [Trash Info]
            Path=\(Self.encode(path))
            DeletionDate=\(Self.dateFormatter.string(from: now()))

            """.utf8)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for counter in 1...10_000 {
            let candidate = counter == 1 ? name : (ext.isEmpty || base.isEmpty ? "\(name).\(counter)" : "\(base).\(counter).\(ext)")
            let file = info.appendingPathComponent(candidate + ".trashinfo")
            let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd < 0 {
                if errno == EEXIST { continue }
                throw Self.error(errno: errno, path: file.path)
            }
            let written = contents.withUnsafeBytes { write(fd, $0.baseAddress, contents.count) }
            close(fd)
            guard written == contents.count else {
                try? FileManager.default.removeItem(at: file)
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
            }
            return (candidate, file)
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: name])
    }

    // MARK: Put Back

    /// Where a trashed item (in some Trash's files/) came from, from its
    /// .trashinfo — written by OneRoot or by any other desktop's Trash.
    func originalLocation(of trashed: URL) -> URL? {
        guard let infoFile = Self.infoFile(for: trashed),
              let text = try? String(contentsOf: infoFile, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("Path=") }) else { return nil }
        let recorded = Self.decode(String(line.dropFirst("Path=".count)))
        guard !recorded.isEmpty else { return nil }
        if recorded.hasPrefix("/") { return URL(fileURLWithPath: recorded) }
        // Relative: to the top of the drive whose Trash this is.
        let trashDirectory = trashed.deletingLastPathComponent().deletingLastPathComponent()
        var top = trashDirectory.deletingLastPathComponent()
        if top.lastPathComponent == ".Trash" { top = top.deletingLastPathComponent() } // .Trash/$uid
        return top.appendingPathComponent(recorded)
    }

    /// Forgets a trashed item once it's been put back or deleted.
    func forget(_ trashed: URL) {
        guard let infoFile = Self.infoFile(for: trashed) else { return }
        try? FileManager.default.removeItem(at: infoFile)
    }

    /// Whether `folder` is a Trash's files/ — the home Trash's, or a
    /// drive's (.Trash-$uid/files, .Trash/$uid/files).
    static func isTrashFiles(_ folder: URL) -> Bool {
        let folder = folder.standardizedFileURL
        guard folder.lastPathComponent == "files" else { return false }
        let trash = folder.deletingLastPathComponent()
        let name = trash.lastPathComponent
        return name == "Trash" || name.hasPrefix(".Trash-")
            || trash.deletingLastPathComponent().lastPathComponent == ".Trash"
    }

    /// The .trashinfo beside `trashed`, if `trashed` is directly in a
    /// Trash's files/.
    static func infoFile(for trashed: URL) -> URL? {
        let files = trashed.deletingLastPathComponent()
        guard files.lastPathComponent == "files" else { return nil }
        return files.deletingLastPathComponent()
            .appendingPathComponent("info", isDirectory: true)
            .appendingPathComponent(trashed.lastPathComponent + ".trashinfo")
    }

    // MARK: Helpers

    /// The spec's "YYYY-MM-DDThh:mm:ss", in local time.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// Percent-encoded like a URL path ("/" kept).
    static func encode(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "/-._~!$&'()*+,;=:@")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    static func decode(_ path: String) -> String {
        path.removingPercentEncoding ?? path
    }

    private static func device(of path: String) -> UInt64? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return UInt64(info.st_dev)
    }

    private static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    /// Creates `url` (and missing parents) readable by this user only.
    private static func makePrivateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path]) }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private static func error(errno code: Int32, path: String) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [
            NSFilePathErrorKey: path,
            NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO),
        ])
    }
}
