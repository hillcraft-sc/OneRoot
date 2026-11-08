import CoreServices
import Foundation

/// What OneRoot can read about one item for the Inspector, beyond what
/// `FileNode` already carries — the readable equivalent of Finder's Get
/// Info. Every value is optional: `nil` (or empty) means it doesn't apply
/// or the system doesn't know it, and the Inspector then shows nothing
/// rather than a guess.
struct ItemDetails: Equatable {
    // General
    /// Folders only: visible (non-hidden) items directly inside.
    var itemCount: Int?
    /// Bytes on disk, which can differ from the file's own size (sparse
    /// files, compression, block rounding).
    var sizeOnDisk: Int64?
    var dateAdded: Date?
    var isAlias = false
    /// Where a symbolic link or alias points.
    var linkDestination: String?
    var cloud: CloudStatus?

    // More info (Spotlight metadata — already extracted by macOS, so
    // nothing is decoded here; an item Spotlight hasn't indexed shows
    // without them)
    var pixelWidth: Int?
    var pixelHeight: Int?
    var resolutionDPI: Int?
    var colorSpace: String?
    var durationSeconds: Double?
    var codecs: [String] = []
    var pageCount: Int?
    var title: String?
    var authors: [String] = []
    /// An app's version.
    var version: String?
    /// Where a download came from (the page and file URLs Safari/Chrome record).
    var whereFroms: [String] = []
    var finderComment: String?

    // Sharing & permissions
    var owner: String?
    var group: String?
    var posixPermissions: Int?
    var isLocked = false
    var hasHiddenExtension = false
}

/// A cloud item's state, as its File Provider reports it — only for items
/// that really are in iCloud Drive or a File Provider location.
enum CloudStatus: Equatable {
    case downloaded
    case cloudOnly
    case downloading
    case uploading

    var description: String {
        switch self {
        case .downloaded: return "Downloaded"
        case .cloudOnly: return "In the cloud only"
        case .downloading: return "Downloading…"
        case .uploading: return "Uploading…"
        }
    }
}

/// UI-agnostic lookup for `ItemDetails`, off the main thread (a network or
/// cloud item's metadata can take a moment).
struct ItemDetailsService {
    func details(for url: URL, isDirectory: Bool) async -> ItemDetails {
        await Task.detached(priority: .userInitiated) {
            Self.read(url, isDirectory: isDirectory)
        }.value
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .addedToDirectoryDateKey,
        .isAliasFileKey, .isSymbolicLinkKey, .hasHiddenExtensionKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemIsUploadingKey,
    ]

    private static func read(_ url: URL, isDirectory: Bool) -> ItemDetails {
        var details = ItemDetails()
        let fileManager = FileManager.default
        // Doesn't follow symbolic links, so a link to something missing
        // still gets its own details.
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return details }
        details.owner = attributes[.ownerAccountName] as? String
        details.group = attributes[.groupOwnerAccountName] as? String
        details.posixPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        details.isLocked = (attributes[.immutable] as? NSNumber)?.boolValue ?? false

        if isDirectory {
            details.itemCount = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.count
        }

        if let values = try? url.resourceValues(forKeys: resourceKeys) {
            if !isDirectory {
                details.sizeOnDisk = (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init)
            }
            details.dateAdded = values.addedToDirectoryDate
            details.isAlias = (values.isAliasFile ?? false) && !(values.isSymbolicLink ?? false)
            details.hasHiddenExtension = values.hasHiddenExtension ?? false
            if values.isUbiquitousItem == true {
                details.cloud = cloudStatus(values)
            }
        }
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            details.linkDestination = destination
        } else if details.isAlias,
                  let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) {
            details.linkDestination = resolved.path
        }

        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            func number(_ key: CFString) -> NSNumber? { MDItemCopyAttribute(item, key) as? NSNumber }
            func string(_ key: CFString) -> String? {
                (MDItemCopyAttribute(item, key) as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            func strings(_ key: CFString) -> [String] {
                (MDItemCopyAttribute(item, key) as? [String] ?? []).filter { !$0.isEmpty }
            }
            details.pixelWidth = number(kMDItemPixelWidth)?.intValue
            details.pixelHeight = number(kMDItemPixelHeight)?.intValue
            details.resolutionDPI = number(kMDItemResolutionWidthDPI).map { Int($0.doubleValue.rounded()) }
            details.colorSpace = string(kMDItemColorSpace)
            details.durationSeconds = number(kMDItemDurationSeconds)?.doubleValue
            details.codecs = strings(kMDItemCodecs)
            details.pageCount = number(kMDItemNumberOfPages)?.intValue
            details.title = string(kMDItemTitle)
            details.authors = strings(kMDItemAuthors)
            details.version = string(kMDItemVersion)
            details.whereFroms = strings(kMDItemWhereFroms)
            details.finderComment = string(kMDItemFinderComment)
        }
        // Spotlight doesn't always index an app's version; its bundle says.
        if details.version == nil, url.pathExtension == "app", let info = Bundle(url: url)?.infoDictionary {
            details.version = info["CFBundleShortVersionString"] as? String
        }
        return details
    }

    private static func cloudStatus(_ values: URLResourceValues) -> CloudStatus {
        if values.ubiquitousItemIsUploading == true { return .uploading }
        if values.ubiquitousItemIsDownloading == true { return .downloading }
        if values.ubiquitousItemDownloadingStatus == .notDownloaded { return .cloudOnly }
        return .downloaded
    }

    /// "0:42", "3:05", "1:02:03" — how media players show a length.
    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Who a permission row is about, Get Info–style.
    enum Audience {
        case owner, group, everyone
    }

    /// "Read & Write", "Read only", "Write only", or "No Access" for one
    /// audience of a POSIX mode — the words Get Info uses.
    static func access(_ permissions: Int, for audience: Audience) -> String {
        let shift: Int
        switch audience {
        case .owner: shift = 6
        case .group: shift = 3
        case .everyone: shift = 0
        }
        let bits = (permissions >> shift) & 0o7
        switch (bits & 0o4 != 0, bits & 0o2 != 0) {
        case (true, true): return "Read & Write"
        case (true, false): return "Read only"
        case (false, true): return "Write only"
        case (false, false): return "No Access"
        }
    }

    /// A download source as people read it: just the site for a web page
    /// ("example.com"), the address itself otherwise.
    static func displaySource(_ source: String) -> String {
        guard let url = URL(string: source), let host = url.host, ["http", "https"].contains(url.scheme ?? "") else {
            return source
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
