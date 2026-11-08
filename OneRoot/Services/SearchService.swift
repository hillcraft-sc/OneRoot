import Foundation

/// One update from an in-flight search: either a match to add to the
/// results list, or a live count of how far the walk has gotten.
enum SearchEvent {
    /// Sent once, first: how this search is being run.
    case engine(SearchEngine)
    case matched(SearchResult)
    /// `.spotlightIndex` only: the index's matches are all in, and the full
    /// scan filling in what it missed starts now.
    case indexPhaseFinished(matches: Int)
    /// `notDownloaded`: cloud files that are only placeholders on this Mac,
    /// which a content search leaves alone rather than make macOS download.
    case progress(foldersScanned: Int, filesScanned: Int, filesSkipped: Int, notDownloaded: Int)
}

/// How a search ran — shown in Advanced Search's status line, since the
/// two can legitimately differ (see `SearchService.search`).
enum SearchEngine: Equatable {
    /// Spotlight's matches first, then a full scan adding whatever the
    /// index missed — it can be incomplete without any way to tell.
    case spotlightIndex
    /// `reason` says why the index wasn't used, when that's worth telling
    /// the user — `nil` when it simply doesn't apply (content search, or
    /// the index turned off).
    case fullScan(reason: String?)
}

enum SearchError: LocalizedError {
    case invalidRegex(String)
    case rootNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .invalidRegex(let pattern):
            return "\"\(pattern)\" isn't a valid regular expression."
        case .rootNotFound(let url):
            return "\(url.path) doesn't exist or isn't a folder."
        }
    }
}

/// UI-agnostic recursive search over a directory tree — file/folder names
/// and metadata, or (in `.contents` mode) a line-by-line grep through file
/// contents. No SwiftUI/AppKit imports — see CLAUDE.md §1. Streams results
/// as they're found rather than collecting them all up front, so a search
/// over a whole volume shows live progress instead of a long silent pause.
struct SearchService {
    private let index: SearchIndexQuerying
    /// The cloud-provider folders (iCloud Drive, Nextcloud, …) to add when
    /// a search asks to include cloud storage. Injectable for tests.
    private let cloudLocations: @Sendable () -> [URL]
    /// Whether a file is only a placeholder, its contents still in the
    /// cloud. Injectable for tests, which can't make a real one.
    private let isDataless: @Sendable (URL) -> Bool

    init(
        index: SearchIndexQuerying = Platform.searchIndex(),
        cloudLocations: @escaping @Sendable () -> [URL] = { CloudStorageLocationsService().discover() },
        isDataless: @escaping @Sendable (URL) -> Bool = { SearchService.fileIsDataless($0) }
    ) {
        self.index = index
        self.cloudLocations = cloudLocations
        self.isDataless = isDataless
    }

    /// `st_flags` bit for a cloud file whose data isn't on disk (macOS's
    /// `SF_DATALESS`). Reading such a file makes the system download it.
    private static let datalessFlag: UInt32 = 0x4000_0000

    static func isDataless(flags: UInt32) -> Bool {
        flags & datalessFlag != 0
    }

    /// Checked with `lstat`, which reads the flag without touching the
    /// file's contents — so asking never triggers a download.
    static func fileIsDataless(_ url: URL) -> Bool {
        #if canImport(Darwin)
        var info = stat()
        return lstat(url.path, &info) == 0 && isDataless(flags: info.st_flags)
        #else
        return false // Linux has no dataless (cloud placeholder) files
        #endif
    }

    /// Running totals across the folders of one search.
    struct ScanCounts {
        var folders = 0
        var files = 0
        var skipped = 0
        var notDownloaded = 0
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The cloud folders to search in addition to walking `criteria.root`:
    /// those *inside* it — what a home or whole-volume search skips, since
    /// they live under the hidden `~/Library`. A search that starts in a
    /// cloud folder (or inside one) already covers it, and one that doesn't
    /// contain any never reaches them. Empty unless the search asks for
    /// cloud storage.
    static func includedCloudRoots(for criteria: SearchCriteria, among locations: [URL]) -> [URL] {
        guard criteria.includeCloudStorage else { return [] }
        let root = criteria.root.resolvingSymlinksInPath().path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        return locations.filter { $0.resolvingSymlinksInPath().path.hasPrefix(rootPrefix) }
    }

    /// Content-mode candidates larger than this are skipped rather than
    /// read — keeps a whole-volume content search from stalling on a huge
    /// log or database file. Counted in `filesSkipped`, not silently dropped.
    private static let maxContentSearchFileSize: Int64 = 20_000_000
    /// Caps matches reported per file in content mode so one file with
    /// thousands of hits doesn't flood the results list and starve progress
    /// on the rest of the tree.
    private static let maxMatchesPerFile = 50
    /// How many entries to scan between `.progress` events — frequent
    /// enough to feel live, infrequent enough not to flood the UI.
    private static let progressInterval = 50

    /// With `useIndex`, a name/metadata search reports Spotlight's matches
    /// first — near-instant even on a whole volume — then walks the tree
    /// anyway and adds only what the index missed. Spotlight's index can be
    /// silently incomplete (whole folders never indexed, items created
    /// seconds ago), so the walk is what guarantees the same results as a
    /// plain full scan; the index just gets most of them on screen in a
    /// fraction of a second. Index candidates are checked against the full
    /// criteria on disk, so they're never *wrong*. Without an index that
    /// can answer, it's just the walk — see `engine(for:useIndex:)`.
    func search(_ criteria: SearchCriteria, useIndex: Bool = false) -> AsyncThrowingStream<SearchEvent, Error> {
        AsyncThrowingStream { [index, cloudLocations, isDataless] continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    // A Workspace searches each of its folders in turn,
                    // counting on from the last; a folder that's gone (an
                    // unplugged drive) is skipped, unless none is there.
                    let roots = criteria.searchRoots
                    let existing = roots.filter { Self.isFolder($0) }
                    var counts = ScanCounts()
                    for root in existing.isEmpty ? [criteria.root] : existing {
                        try Task.checkCancellation()
                        var single = criteria
                        single.root = root
                        single.additionalRoots = []
                        let cloudRoots = Self.includedCloudRoots(for: single, among: single.includeCloudStorage ? cloudLocations() : [])
                        try await Self.run(
                            single, useIndex: useIndex, index: index,
                            cloudRoots: cloudRoots, isDataless: isDataless, counts: &counts, continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        _ criteria: SearchCriteria,
        useIndex: Bool,
        index: SearchIndexQuerying,
        cloudRoots: [URL],
        isDataless: @Sendable (URL) -> Bool,
        counts: inout ScanCounts,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: criteria.root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SearchError.rootNotFound(criteria.root)
        }

        let matcher = try SearchCriteriaMatcher(criteria)

        /// Paths the index phase already reported, so the walk skips them.
        var alreadyFound: Set<String> = []
        var fallbackReason: String?
        switch engine(for: criteria, useIndex: useIndex) {
        case .spotlightIndex:
            let query = SpotlightQueryBuilder.query(for: criteria) ?? ""
            let root = criteria.root.resolvingSymlinksInPath()
            if let paths = index.paths(matching: query, under: root) {
                continuation.yield(.engine(.spotlightIndex))
                alreadyFound = try runIndexed(
                    paths, root: root, cloudRoots: cloudRoots, criteria: criteria, matcher: matcher,
                    isDataless: isDataless, continuation: continuation
                )
                continuation.yield(.indexPhaseFinished(matches: alreadyFound.count))
            } else {
                fallbackReason = "this location isn't indexed by Spotlight"
                continuation.yield(.engine(.fullScan(reason: fallbackReason)))
            }
        case .fullScan(let reason):
            continuation.yield(.engine(.fullScan(reason: reason)))
        }

        var foldersScanned = counts.folders
        var filesScanned = counts.files
        var filesSkipped = counts.skipped
        var notDownloaded = counts.notDownloaded
        defer {
            counts = ScanCounts(folders: foldersScanned, files: filesScanned, skipped: filesSkipped, notDownloaded: notDownloaded)
        }

        func walk(_ walkRoot: URL) async throws {
            guard let enumerator = FileManager.default.enumerator(
                at: walkRoot,
                includingPropertiesForKeys: FileSystemService.resourceKeys,
                options: criteria.includeHidden ? [] : [.skipsHiddenFiles],
                errorHandler: { _, _ in true } // keep walking past unreadable items rather than aborting the whole search
            ) else {
                return
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let node = FileSystemService.makeNode(for: url)

                if node.isDirectory {
                    foldersScanned += 1
                } else {
                    filesScanned += 1
                }
                if (foldersScanned + filesScanned) % progressInterval == 0 {
                    continuation.yield(.progress(foldersScanned: foldersScanned, filesScanned: filesScanned, filesSkipped: filesSkipped, notDownloaded: notDownloaded))
                }

                guard matcher.passesFilters(node) else { continue }

                switch criteria.mode {
                case .nameAndMetadata:
                    // Folders are real, matchable results here — only content
                    // search (grepping a file's lines) is meaningless for them.
                    guard matcher.matchesItemType(node), matcher.matchesName(node.name) else { continue }
                    guard alreadyFound.isEmpty || !alreadyFound.contains(indexComparablePath(url)) else { continue }
                    continuation.yield(.matched(SearchResult(node: node, contentMatch: nil, isCloudOnly: !node.isDirectory && isDataless(url))))
                case .contents:
                    guard !node.isDirectory, !criteria.pattern.isEmpty else { continue }
                    do {
                        try await searchContents(
                            of: node, matcher: matcher, continuation: continuation,
                            isDataless: isDataless, filesSkipped: &filesSkipped, notDownloaded: &notDownloaded
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        filesSkipped += 1
                    }
                }
            }
        }

        try await walk(criteria.root)
        // With hidden items included, the walk above already went through
        // ~/Library and so through the cloud folders; otherwise they need
        // their own visit.
        if !criteria.includeHidden {
            for cloudRoot in cloudRoots {
                try await walk(cloudRoot)
            }
        }

        continuation.yield(.progress(foldersScanned: foldersScanned, filesScanned: filesScanned, filesSkipped: filesSkipped, notDownloaded: notDownloaded))
    }

    /// Whether a search can use the index, and if not, why — before
    /// asking the index itself, which can still turn out not to cover the
    /// root (see `SpotlightIndex`).
    static func engine(for criteria: SearchCriteria, useIndex: Bool) -> SearchEngine {
        guard useIndex, criteria.mode == .nameAndMetadata else { return .fullScan(reason: nil) }
        if criteria.includeHidden {
            return .fullScan(reason: "Spotlight doesn't index hidden files")
        }
        if criteria.patternMode == .regex, !criteria.pattern.isEmpty {
            return .fullScan(reason: "Spotlight can't search by regex")
        }
        guard SpotlightQueryBuilder.query(for: criteria) != nil else {
            return .fullScan(reason: "Spotlight needs a name, extension, or minimum size to search by")
        }
        return .spotlightIndex
    }

    /// Checks each index candidate against the real file and the same
    /// filters the walk applies — the index may be stale (an item since
    /// deleted or renamed) or broader than the criteria (case, diacritics).
    /// Returns the paths it reported, in `indexComparablePath` form.
    private static func runIndexed(
        _ paths: [String],
        root: URL,
        cloudRoots: [URL],
        criteria: SearchCriteria,
        matcher: SearchCriteriaMatcher,
        isDataless: @Sendable (URL) -> Bool,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) throws -> Set<String> {
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let cloudPrefixes = cloudRoots.map { cloudRoot -> String in
            let path = cloudRoot.resolvingSymlinksInPath().path
            return path.hasSuffix("/") ? path : path + "/"
        }
        var found: Set<String> = []
        var hiddenByPath: [String: Bool] = [:]

        for path in paths.sorted() {
            try Task.checkCancellation()
            guard path.hasPrefix(rootPrefix) else { continue }
            // The walk skips hidden items and everything inside them —
            // dot-names, and also folders macOS flags hidden, like
            // ~/Library — so the indexed path has to as well. Except inside
            // a cloud folder the search asked to include: the hidden
            // ~/Library above it is exempt, and the rules apply from there.
            let checkedFrom = cloudPrefixes.first { path.hasPrefix($0) } ?? rootPrefix
            let relativeComponents = path.dropFirst(checkedFrom.count).split(separator: "/")
            guard !relativeComponents.contains(where: { $0.hasPrefix(".") }) else { continue }
            var ancestor = String(checkedFrom.dropLast())
            let isUnderHiddenItem = relativeComponents.contains { component in
                ancestor += (ancestor.hasSuffix("/") ? "" : "/") + component
                if let cached = hiddenByPath[ancestor] { return cached }
                let hidden = (try? URL(fileURLWithPath: ancestor).resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
                hiddenByPath[ancestor] = hidden
                return hidden
            }
            guard !isUnderHiddenItem else { continue }

            let url = URL(fileURLWithPath: path)
            guard (try? url.checkResourceIsReachable()) == true else { continue }
            let node = FileSystemService.makeNode(for: url)
            guard matcher.matches(node) else { continue }
            continuation.yield(.matched(SearchResult(node: node, contentMatch: nil, isCloudOnly: !node.isDirectory && isDataless(url))))
            found.insert(path)
        }
        return found
    }

    /// The walk's URLs are spelled from the root as given (`/tmp/…`),
    /// Spotlight's resolved (`/private/tmp/…`) — so resolve the walk's
    /// parent folder to compare. Only the parent: a symlink item itself is
    /// reported by both as the link, not its target.
    private static func indexComparablePath(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }

    /// Streams matching lines out of one candidate file, skipping (and
    /// counting) it up front if it's not text or is too large to be worth
    /// reading.
    private static func searchContents(
        of node: FileNode,
        matcher: SearchCriteriaMatcher,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation,
        isDataless: @Sendable (URL) -> Bool,
        filesSkipped: inout Int,
        notDownloaded: inout Int
    ) async throws {
        // A cloud placeholder: reading it would make macOS download it, so a
        // content search leaves it alone — counted separately from the
        // binary/oversized files, so the status line can say so.
        if isDataless(node.url) {
            notDownloaded += 1
            return
        }
        guard let size = node.size, size <= maxContentSearchFileSize, isLikelyText(node.url) else {
            filesSkipped += 1
            return
        }

        var lineNumber = 0
        var matchesInFile = 0
        /// One line; `false` once the file has given enough matches.
        func check(_ line: String) throws -> Bool {
            try Task.checkCancellation()
            lineNumber += 1
            guard matcher.matchesLine(line) else { return true }
            continuation.yield(.matched(SearchResult(
                node: node,
                contentMatch: ContentMatch(lineNumber: lineNumber, snippet: line.trimmingCharacters(in: .whitespaces))
            )))
            matchesInFile += 1
            return matchesInFile < maxMatchesPerFile
        }
        #if canImport(Darwin)
        let handle = try FileHandle(forReadingFrom: node.url)
        defer { try? handle.close() }
        for try await line in handle.bytes.lines {
            guard try check(line) else { break }
        }
        #else
        // Linux has no async byte stream; the file is already known to be
        // small enough (maxContentSearchFileSize) to read whole.
        let text = (try? String(contentsOf: node.url, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard try check(String(line)) else { break }
        }
        #endif
    }

    private static func isLikelyText(_ url: URL) -> Bool {
        Platform.isLikelyText(url)
    }
}
