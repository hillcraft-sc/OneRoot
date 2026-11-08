import Foundation

/// What a folder holds, as `StorageScanner` adds it up: by item, by kind of
/// file, by age, by tag, and by cloud state. Sizes are logical sizes (what
/// the file list shows), so a cloud-only file counts at its full size —
/// the Cloud breakdown says how much of that isn't on this Mac.
struct StorageReport: Equatable {
    let root: URL
    var scannedAt = Date()
    /// False while the scan is still going (or was stopped).
    var isComplete = false
    var totalSize: Int64 = 0
    var fileCount = 0
    var folderCount = 0
    /// Items that couldn't be read (permissions, a share dropping out).
    var unreadableCount = 0
    /// The folder's own items, largest first.
    var children: [StorageEntry] = []
    var categories: [StorageCategory: StorageBucket] = [:]
    var ages: [StorageAge: StorageBucket] = [:]
    var tags: [String: StorageBucket] = [:]
    var untagged = StorageBucket()
    var cloud: [StorageCloudState: StorageBucket] = [:]

    init(root: URL) {
        self.root = root
    }

    /// Whether anything here is synced by a cloud provider.
    var hasCloudItems: Bool {
        (cloud[.downloaded]?.count ?? 0) + (cloud[.cloudOnly]?.count ?? 0) > 0
    }
}

/// One of the scanned folder's own items, with everything inside it.
struct StorageEntry: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    var size: Int64
    var fileCount: Int
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// A file listed among a bucket's largest.
struct StorageFile: Identifiable, Equatable {
    let url: URL
    let size: Int64
    var id: URL { url }
}

/// Total size and count of the files in one group, and the largest few.
struct StorageBucket: Equatable {
    var size: Int64 = 0
    var count = 0
    /// Largest first, at most `largestLimit`.
    var largest: [StorageFile] = []

    static let largestLimit = 20

    mutating func add(_ file: StorageFile) {
        size += file.size
        count += 1
        guard largest.count < Self.largestLimit || file.size > (largest.last?.size ?? 0) else { return }
        let index = largest.firstIndex { $0.size < file.size } ?? largest.endIndex
        largest.insert(file, at: index)
        if largest.count > Self.largestLimit { largest.removeLast() }
    }
}

/// How long since a file was last changed.
enum StorageAge: CaseIterable, Identifiable {
    case thisWeek, thisMonth, thisYear, older, unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .thisWeek: return "This week"
        case .thisMonth: return "This month"
        case .thisYear: return "This year"
        case .older: return "Over a year ago"
        case .unknown: return "Unknown"
        }
    }

    static func of(_ modified: Date?, now: Date) -> StorageAge {
        guard let modified else { return .unknown }
        let days = now.timeIntervalSince(modified) / 86_400
        if days < 7 { return .thisWeek }
        if days < 30 { return .thisMonth }
        if days < 365 { return .thisYear }
        return .older
    }
}

/// Where a file's contents are, for cloud-synced folders.
enum StorageCloudState: CaseIterable, Identifiable {
    /// Synced, and on this Mac.
    case downloaded
    /// Synced, but only a placeholder here — it takes no space until opened.
    case cloudOnly
    /// Not synced by any provider.
    case notInCloud

    var id: Self { self }

    var title: String {
        switch self {
        case .downloaded: return "Downloaded"
        case .cloudOnly: return "In the cloud only"
        case .notInCloud: return "Not in the cloud"
        }
    }
}
