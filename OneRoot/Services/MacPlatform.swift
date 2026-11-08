#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers

/// What OneRoot needs from the operating system that differs between
/// macOS and Linux (#79). Shared code calls `Platform`; this file is the
/// macOS side — the code that was here all along — and LinuxPlatform.swift
/// the Linux side, with the same members. Both live in Services/.
enum Platform {
    /// Moves an item to the Trash and returns where it went.
    static func trashItem(_ url: URL) throws -> URL? {
        var resultingItemURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingItemURL)
        return resultingItemURL as URL?
    }

    /// The Trash folder in the sidebar.
    static var trashFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// The Mac always has a Trash folder.
    static func ensureTrashFolderExists() {}

    /// Whether `folder` is a Trash (where Put Back and Delete Immediately
    /// apply, and Quick Actions don't) — ~/.Trash or a volume's .Trashes.
    static func isTrashFolder(_ folder: URL) -> Bool {
        folder.lastPathComponent == ".Trash"
    }

    /// macOS keeps no record a third-party app can read of where a trashed
    /// item came from (see `TrashOriginService`).
    static func trashedItemOrigin(_ trashed: URL) -> URL? { nil }

    static func forgetTrashedItem(_ trashed: URL) {}

    /// Copies one item (folders recursively) with progress and Cancel —
    /// `copyfile(3)`, cloning on APFS.
    static func copyItem(
        _ source: URL,
        to destination: URL,
        includeMetadata: Bool,
        cancellation: CancellationFlag,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        try FileCopier.copy(source, to: destination, includeMetadata: includeMetadata, cancellation: cancellation, onProgress: onProgress)
    }

    /// Whether the destination's volume stores extended attributes itself.
    static func storesMetadataNatively(_ url: URL) -> Bool {
        FileCopier.storesMetadataNatively(url)
    }

    /// When an item was last opened, by Spotlight (Finder's Date Last Opened).
    static func lastUsedDate(atPath path: String) -> Date? {
        SpotlightIndex.lastUsedDate(atPath: path)
    }

    /// A Finder alias at `alias` pointing to `target`.
    static func makeAlias(to target: URL, at alias: URL) throws {
        let data = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: alias)
    }

    /// Which kind of file an extension is, by its UTType.
    static func storageCategory(forExtension fileExtension: String) -> StorageCategory {
        StorageCategory.of(UTType(filenameExtension: fileExtension))
    }

    /// Whether a file is text, for content search (its UTType).
    /// Resource keys a storage scan also needs to tell file types apart.
    static let fileTypeKeys: [URLResourceKey] = [.contentTypeKey]

    /// A scanned file's category, from the keys above.
    static func storageCategory(of url: URL, values: URLResourceValues) -> StorageCategory {
        StorageCategory.of(values.contentType)
    }

    static func isLikelyText(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .text)
    }

    /// Spotlight, for search and Recents.
    static func searchIndex() -> SearchIndexQuerying & RecentItemsQuerying {
        SpotlightIndex()
    }

    /// Folders like Mail.app or a Photos library are single documents
    /// ("packages") here: opened, not browsed into.
    static let hasPackages = true

    /// "PNG image", "Folder" — Launch Services' name for the item's type.
    static func kind(of url: URL, values: URLResourceValues?) -> String? {
        values?.localizedTypeDescription
    }

    /// Compress and Extract: Finder's own engine.
    static let defaultArchiveTool = ArchiveTool.appleDitto

    // MARK: Tags (Finder's)

    static func tags(of url: URL) throws -> [String] {
        var url = url
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    /// `URLResourceValues.tagNames` is read-only in Swift; the `NSURL` key
    /// is the supported way to write it.
    static func setTags(_ tags: [String], on url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// A listing's tags, from the values it prefetched.
    static func listedTags(of url: URL, values: URLResourceValues?) -> [String] {
        values?.tagNames ?? []
    }

    /// A watcher for live refresh: FSEvents.
    static func makeFileWatcher() -> FileWatching { FileWatcher() }

    /// Mounted volumes, kept current.
    static func volumes() -> VolumeProviding { VolumeService() }

    /// The mounted volumes right now (reads the disk; keep off the main
    /// actor).
    static func currentVolumes() -> [VolumeInfo] { VolumeService.currentVolumes() }

    // MARK: The destinations sidebar

    /// Listed under Locations.
    static let applicationsFolder: URL? = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// Lists shown under Home (Spotlight's).
    static let virtualDestinations: [VirtualLocation] = [.recents, .shared]

    /// Where Recents looks: the home folder (and the cloud folders in it).
    static func recentsRoots(home: URL) -> [URL] { [home] }

    /// Folders listed under Home after it: none — Finder users pin their own.
    static func userFolders(home: URL) -> [URL] { [] }

    /// The system clipboard.
    @MainActor static let clipboard: FileClipboard = PasteboardClipboard(.general)

    // MARK: Questions and notices (NSAlert)

    /// Move to Trash, confirmed first: a folder with enough in it can be
    /// hard to rebuild after an accidental ⌫. `true` means go ahead.
    @MainActor static func confirmTrash(_ names: [String]) -> Bool {
        guard !names.isEmpty else { return false }
        let alert = NSAlert()
        alert.messageText = names.count == 1
            ? "Move \u{201C}\(names[0])\u{201D} to the Trash?"
            : "Move \(names.count) items to the Trash?"
        alert.informativeText = names.count == 1
            ? "You can restore it from the Trash later."
            : "You can restore them from the Trash later."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// For items on a volume with no Trash (network shares, mostly): the
    /// only way to remove them is to delete them for good, so say so and
    /// ask again. `true` means delete.
    @MainActor static func confirmDeleteWithoutTrash(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = urls.count == 1
            ? "\u{201C}\(urls[0].lastPathComponent)\u{201D} can\u{2019}t be moved to the Trash. Delete it immediately?"
            : "\(urls.count) items can\u{2019}t be moved to the Trash. Delete them immediately?"
        alert.informativeText = "The volume \(urls.count == 1 ? "it\u{2019}s" : "they\u{2019}re") on doesn\u{2019}t have a Trash (common for network shares). This can\u{2019}t be undone."
        alert.addButton(withTitle: "Delete Immediately")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Something went wrong that the user should hear about — on the front
    /// window if there is one.
    @MainActor static func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// The progress windows and File Operations card.
    @MainActor static var progress: FileOperationProgressReporting {
        FileOperationProgressCenter.shared
    }
}

/// Which category a file type belongs to (Apple platforms: UTType).
extension StorageCategory {
    static func of(_ type: UTType?) -> StorageCategory {
        guard let type else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) || type.conforms(to: .executable) { return .apps }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) || type.conforms(to: .xml) { return .code }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .presentation) || type.conforms(to: .compositeContent) || type.conforms(to: .rtf) {
            return .documents
        }
        return .other
    }
}
#endif
