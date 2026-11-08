import Foundation

/// Lists a `VirtualLocation` — for the file list, off the main actor.
protocol VirtualListing: Sendable {
    func items(for location: VirtualLocation) async throws -> [FileNode]
}

/// Recents from Spotlight's "last opened" dates; Shared from iCloud Drive
/// items macOS marks as shared. Nothing is guessed: other cloud services
/// don't report sharing, so Shared covers iCloud Drive only.
struct VirtualListingService: VirtualListing {
    /// How far back Recents goes.
    static let recentDays = 30
    /// Recents keeps the most recently opened this many.
    static let recentLimit = 500

    private let index: RecentItemsQuerying
    private let home: URL
    private let iCloudDrive: URL

    init(
        index: RecentItemsQuerying = Platform.searchIndex(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        iCloudDrive: URL? = nil
    ) {
        self.index = index
        self.home = home
        self.iCloudDrive = iCloudDrive ?? home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    func items(for location: VirtualLocation) async throws -> [FileNode] {
        switch location {
        case .recents: return try recents()
        case .shared: return try shared()
        }
    }

    /// What you've opened in the last 30 days, newest first, the way
    /// Finder's Recents works: files (and apps, documents that are
    /// packages) in your home folder and its cloud folders — iCloud Drive
    /// and `~/Library/CloudStorage` — but not the rest of `~/Library` or
    /// hidden items, which are app data. Ordered and dated by Spotlight's
    /// last-used date, as Finder is. (A File Provider service that keeps
    /// its own index, like Nextcloud's, isn't visible to Spotlight here.)
    func recents() throws -> [FileNode] {
        let library = home.appendingPathComponent("Library").path + "/"
        let cloudFolders = [iCloudDrive, home.appendingPathComponent("Library/CloudStorage", isDirectory: true)]
        let cloudPrefixes = cloudFolders.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        let found = index.recentlyUsed(withinDays: Self.recentDays, under: Platform.recentsRoots(home: home))
        try Task.checkCancellation()
        var newest: [String: Date] = [:]
        for (path, date) in found {
            let inCloud = cloudPrefixes.contains { path.hasPrefix($0) }
            guard !path.hasPrefix(library) || inCloud else { continue }
            let checkedFrom = cloudPrefixes.first { path.hasPrefix($0) } ?? (path.hasPrefix(home.path + "/") ? home.path + "/" : "/")
            guard !path.dropFirst(checkedFrom.count).split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { continue }
            newest[path] = max(newest[path] ?? .distantPast, date)
        }
        let nodes = newest
            .sorted { $0.value > $1.value }
            .prefix(Self.recentLimit * 2)
            .map { FileSystemService.makeNode(for: URL(fileURLWithPath: $0.key)).withLastOpened($0.value) }
            .filter { !$0.isDirectory || $0.isPackage }
        return Array(nodes.prefix(Self.recentLimit))
    }

    /// Items in iCloud Drive shared with you or by you. A shared folder is
    /// listed itself, not everything in it.
    func shared() throws -> [FileNode] {
        #if !canImport(Darwin)
        return [] // iCloud Drive sharing is Apple-only
        #else
        guard FileManager.default.fileExists(atPath: iCloudDrive.path),
              let enumerator = FileManager.default.enumerator(
                  at: iCloudDrive,
                  includingPropertiesForKeys: [.ubiquitousItemIsSharedKey, .isDirectoryKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
                  errorHandler: { _, _ in true }
              )
        else { return [] }
        var found: [FileNode] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard (try? url.resourceValues(forKeys: [.ubiquitousItemIsSharedKey]))?.ubiquitousItemIsShared == true else { continue }
            let node = FileSystemService.makeNode(for: url)
            found.append(node)
            if node.isDirectory { enumerator.skipDescendants() }
        }
        return found
        #endif
    }
}
