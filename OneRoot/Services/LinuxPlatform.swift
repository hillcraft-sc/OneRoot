#if os(Linux)
import Foundation

/// The Linux side of `Platform` (see MacPlatform.swift). These are first
/// versions so the shared code builds and runs; the full Linux
/// implementations — freedesktop Trash, a copy engine with progress,
/// xattrs — come in phase 4 (#81).
enum Platform {
    /// The freedesktop.org Trash (see `FreedesktopTrash`).
    static func trashItem(_ url: URL) throws -> URL? {
        try FreedesktopTrash.system().trash(url)
    }

    /// The home Trash's items: ~/.local/share/Trash/files.
    static var trashFolder: URL { FreedesktopTrash.system().homeTrashFiles }

    /// Creates the Trash folder if a fresh account doesn't have one yet.
    static func ensureTrashFolderExists() {
        FreedesktopTrash.system().ensureHomeTrashExists()
    }

    /// Whether `folder` is a Trash (where Put Back and Delete Immediately
    /// apply, and Quick Actions don't).
    static func isTrashFolder(_ folder: URL) -> Bool {
        FreedesktopTrash.isTrashFiles(folder)
    }

    /// Where a trashed item came from, from its .trashinfo — also for items
    /// another app trashed.
    static func trashedItemOrigin(_ trashed: URL) -> URL? {
        FreedesktopTrash.system().originalLocation(of: trashed)
    }

    /// Drops a trashed item's .trashinfo once it's put back or deleted.
    static func forgetTrashedItem(_ trashed: URL) {
        FreedesktopTrash.system().forget(trashed)
    }

    /// Copies one item (folders recursively) with progress, Pause and
    /// Cancel, keeping dates, permissions and attributes (`LinuxFileCopier`).
    static func copyItem(
        _ source: URL,
        to destination: URL,
        includeMetadata: Bool,
        cancellation: CancellationFlag,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        try LinuxFileCopier.copy(source, to: destination, includeMetadata: includeMetadata, cancellation: cancellation, onProgress: onProgress)
    }

    /// Whether the destination's file system keeps `user.*` attributes.
    static func storesMetadataNatively(_ url: URL) -> Bool {
        LinuxFileCopier.storesMetadataNatively(url)
    }

    /// No Spotlight on Linux; Date Last Opened is the access time.
    static func lastUsedDate(atPath path: String) -> Date? {
        nil
    }

    /// Linux has no aliases; a symbolic link is the closest thing.
    /// Like a Finder alias, it needs something to point to.
    static func makeAlias(to target: URL, at alias: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: target.path])
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
    }

    /// By the type the shared MIME database gives the extension; the
    /// common extensions where it has none.
    static func storageCategory(forExtension fileExtension: String) -> StorageCategory {
        guard !fileExtension.isEmpty, let type = MimeDatabase.shared.type(forFileName: "x." + fileExtension) else {
            return StorageCategory.common(forExtension: fileExtension)
        }
        return StorageCategory.of(mimeType: type) ?? StorageCategory.common(forExtension: fileExtension)
    }

    /// Resource keys a storage scan also needs to tell file types apart:
    /// none, the extension does it (see `storageCategory(forExtension:)`).
    static let fileTypeKeys: [URLResourceKey] = []

    static func storageCategory(of url: URL, values: URLResourceValues) -> StorageCategory {
        storageCategory(forExtension: url.pathExtension)
    }

    /// Whether a file is text, for content search: its first 8 KB has no
    /// NUL bytes and reads as UTF-8 (cut mid-character at the end is fine).
    static func isLikelyText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let sample = try? handle.read(upToCount: 8192) else { return true } // empty
        if sample.contains(0) { return false }
        for trim in 0...3 where sample.count >= trim {
            if String(data: sample.dropLast(trim), encoding: .utf8) != nil { return true }
        }
        return false
    }

    /// No search index (search walks the folders); Recents come from
    /// ~/.local/share/recently-used.xbel.
    static func searchIndex() -> SearchIndexQuerying & RecentItemsQuerying {
        RecentlyUsedIndex()
    }

    /// Progress for copies, moves and the rest: the same center the Mac
    /// uses; the Linux app shows it in its File Operations panel.
    @MainActor static var progress: FileOperationProgressReporting {
        FileOperationProgressCenter.shared
    }
    /// "PNG image", "Folder" — from the shared MIME database.
    static func kind(of url: URL, values: URLResourceValues?) -> String? {
        MimeDatabase.shared.kind(forFileName: url.lastPathComponent, isDirectory: values?.isDirectory ?? false)
    }

    /// Compress and Extract: libarchive, on every Linux desktop.
    static let defaultArchiveTool = ArchiveTool.libarchive

    // MARK: Tags (user.xdg.tags, as KDE keeps them)

    static func tags(of url: URL) throws -> [String] { XDGTags.tags(of: url) }

    static func setTags(_ tags: [String], on url: URL) throws { try XDGTags.setTags(tags, on: url) }

    static func listedTags(of url: URL, values: URLResourceValues?) -> [String] { XDGTags.tags(of: url) }

    /// A watcher for live refresh: inotify.
    static func makeFileWatcher() -> FileWatching { InotifyWatcher() }

    /// No packages on Linux: a folder named Tool.app is just a folder
    /// (Foundation there still calls it a package by its extension).
    static let hasPackages = false

    /// The mounted drives and shares (see `LinuxVolumeService`).
    static func volumes() -> VolumeProviding { LinuxVolumeService() }

    static func currentVolumes() -> [VolumeInfo] { LinuxVolumeService.currentVolumes() }

    // MARK: The destinations sidebar

    /// No /Applications folder on Linux.
    static let applicationsFolder: URL? = nil

    /// Recents (from recently-used.xbel). No Shared: it is iCloud Drive's.
    static let virtualDestinations: [VirtualLocation] = [.recents]

    /// Where Recents looks: anywhere. recently-used.xbel is the user's own
    /// record of what they opened, including files on other drives.
    static func recentsRoots(home: URL) -> [URL] { [URL(fileURLWithPath: "/", isDirectory: true)] }

    /// Desktop, Documents, Downloads, … (xdg-user-dirs), under Home as in
    /// Nautilus and Dolphin. Reads the disk.
    static func userFolders(home: URL) -> [URL] { XDGUserDirectories.current(home: home) }

    /// The desktop's clipboard, set by the Linux app at launch (before any
    /// view model is made); in-process until then, and in tests.
    @MainActor static var clipboard: FileClipboard = MemoryClipboard()

    // MARK: Questions and notices

    /// Set by the Linux app at launch to its own dialogs.
    /// Until then every question gets the safe answer — no — and notices
    /// go to standard error, so nothing is ever deleted without being asked.
    @MainActor static var confirmTrashHandler: ([String]) -> Bool = { _ in false }
    @MainActor static var confirmDeleteWithoutTrashHandler: ([URL]) -> Bool = { _ in false }
    @MainActor static var showErrorHandler: (String, String) -> Void = { title, message in
        FileHandle.standardError.write(Data("\(title): \(message)\n".utf8))
    }

    @MainActor static func confirmTrash(_ names: [String]) -> Bool {
        !names.isEmpty && confirmTrashHandler(names)
    }

    @MainActor static func confirmDeleteWithoutTrash(_ urls: [URL]) -> Bool {
        !urls.isEmpty && confirmDeleteWithoutTrashHandler(urls)
    }

    @MainActor static func showError(_ title: String, _ message: String) {
        showErrorHandler(title, message)
    }
}

struct NoSearchIndex: SearchIndexQuerying, RecentItemsQuerying {
    func paths(matching query: String, under root: URL) -> [String]? { nil }
    func recentlyUsed(withinDays days: Int, under roots: [URL]) -> [(path: String, lastUsed: Date)] { [] }
}

#endif
