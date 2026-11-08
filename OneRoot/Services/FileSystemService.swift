import Foundation

/// UI-agnostic file system access. No SwiftUI/AppKit imports — see CLAUDE.md
/// §1. All work runs off the main actor; callers await the result.
struct FileSystemService {
    /// Settings ▸ General: show Spotlight's last-opened date (Finder's)
    /// in Date Last Opened, instead of the file's last access time — which
    /// anything reading a file updates. Off by default: it's a Spotlight
    /// lookup per item as a folder loads.
    static let usesSpotlightLastOpenedKey = "com.oneroot.fileList.usesSpotlightLastOpened"

    /// Read at each listing; injectable for tests.
    var usesSpotlightLastOpened: @Sendable () -> Bool = {
        UserDefaults.standard.bool(forKey: FileSystemService.usesSpotlightLastOpenedKey)
    }
    var spotlightLastUsedDate: @Sendable (String) -> Date? = { Platform.lastUsedDate(atPath: $0) }

    /// Moves an item to the Trash and returns where it went. Replace in a
    /// copy/move sends the item it replaces here; injectable so tests
    /// don't fill the real Trash.
    /// Settings ▸ General ▸ Verify copies (off by default); injectable for tests.
    var verifiesCopies: @Sendable () -> Bool = { UserDefaults.standard.bool(forKey: FileVerifier.enabledKey) }
    /// Settings ▸ General ▸ Copy to the same disk one at a time (on by
    /// default); injectable for tests.
    var queuesTransfers: @Sendable () -> Bool = { FileTransferQueue.isEnabled }
    var transferQueue = FileTransferQueue.shared
    /// Settings ▸ General ▸ Keep Mac metadata on network shares (off by
    /// default): when off, copies to a share that can't store extended
    /// attributes natively (NFS) leave them out — see `FileCopier.copy`.
    static let keepsMetadataOnSharesKey = "com.oneroot.fileOperations.keepMetadataOnShares"
    var keepsMetadataOnShares: @Sendable () -> Bool = { UserDefaults.standard.bool(forKey: FileSystemService.keepsMetadataOnSharesKey) }
    /// Injectable for tests (whose folders are all on one disk).
    var storesMetadataNatively: @Sendable (URL) -> Bool = { Platform.storesMetadataNatively($0) }
    /// Where copies and moves show their progress (`Platform.progress`);
    /// injectable for tests.
    var progress: @MainActor @Sendable () -> FileOperationProgressReporting = { Platform.progress }
    /// Tests only: verify copies within one disk too (normally clones,
    /// skipped), since a test's temporary folders are all on one disk.
    var verifiesSameDiskCopies = false

    var trashItem: @Sendable (URL) throws -> URL? = { try Platform.trashItem($0) }

    /// Internal rather than private so `SearchService` can prefetch the same
    /// keys while walking a tree with `FileManager.enumerator`, and build
    /// `FileNode`s the same way `listDirectory` does via `makeNode` below.
    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
        .nameKey,
        .creationDateKey,
        .addedToDirectoryDateKey,
        .contentAccessDateKey,
        .tagNamesKey,
    ]

    /// `wantsLastOpenedDates`: the caller shows, sorts, or groups by Date
    /// Last Opened. Only then is Spotlight asked (with Settings ▸ General's
    /// Spotlight option on) — a lookup per item, which on a 50,000-file
    /// folder took 20 seconds when every listing did it (#72).
    func listDirectory(_ url: URL, includeHidden: Bool = false, wantsLastOpenedDates: Bool = false) async throws -> [FileNode] {
        let spotlightDates = wantsLastOpenedDates && usesSpotlightLastOpened()
        let lastUsedDate = spotlightLastUsedDate
        return try await Task.detached(priority: .userInitiated) {
            let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
            var contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: options
                )
            } catch {
                throw FileSystemError.cannotList(url, underlying: error)
            }

            // Finder's "Applications" is a composite of `/Applications`
            // (what you install yourself, plus a handful of Apple apps)
            // and `/System/Applications` (most of Apple's built-in apps,
            // which have lived on the separate read-only System volume
            // since Catalina) — a plain directory read of just
            // `/Applications` only shows the former. Best-effort: if
            // `/System/Applications` can't be read for some reason,
            // `/Applications` itself still lists normally.
            if url.standardizedFileURL.path == Self.applicationsURL.path,
               let systemApps = try? FileManager.default.contentsOfDirectory(
                   at: Self.systemApplicationsURL,
                   includingPropertiesForKeys: Self.resourceKeys,
                   options: options
               ) {
                let existingNames = Set(contents.map(\.lastPathComponent))
                contents += systemApps.filter { !existingNames.contains($0.lastPathComponent) }
            }

            let nodes = contents.map(Self.makeNode)
            let dated = spotlightDates ? Self.withSpotlightDates(nodes, lookup: lastUsedDate) : nodes
            return dated.sorted(by: Self.byFolderThenName)
        }.value
    }

    /// Spotlight's last-opened dates for `nodes`, looked up on several
    /// threads at once (each lookup waits on Spotlight's index, not CPU).
    private static func withSpotlightDates(_ nodes: [FileNode], lookup: @Sendable (String) -> Date?) -> [FileNode] {
        guard !nodes.isEmpty else { return nodes }
        let dates = UnsafeMutableBufferPointer<Date?>.allocate(capacity: nodes.count)
        dates.initialize(repeating: nil)
        defer { dates.deallocate() }
        let chunk = 256
        let chunks = (nodes.count + chunk - 1) / chunk
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for position in (index * chunk)..<min((index + 1) * chunk, nodes.count) {
                dates[position] = lookup(nodes[position].url.path)
            }
        }
        return nodes.enumerated().map { $0.element.withLastOpened(dates[$0.offset]) }
    }

    private static let applicationsURL = URL(fileURLWithPath: "/Applications")
    private static let systemApplicationsURL = URL(fileURLWithPath: "/System/Applications")

    /// Immediate subfolder names of `directory` — for the address bar's
    /// autocomplete dropdown as the user types. Deliberately lighter than
    /// `listDirectory`: fetches only `.isDirectoryKey` (you can't
    /// navigate into a file, so files are skipped entirely) and returns
    /// bare names instead of full `FileNode`s. Best-effort — a missing or
    /// unreadable directory just yields no suggestions rather than an
    /// error, since this drives a dropdown, not a file list.
    func suggestFolders(in directory: URL, includeHidden: Bool = false) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: includeHidden ? [] : [.skipsHiddenFiles]
            ) else { return [] }
            return contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .map(\.lastPathComponent)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }.value
    }

    /// Creates a new folder in `directory`, auto-numbering ("New Folder",
    /// "New Folder (2)", …) if `name` is already taken.
    @discardableResult
    func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let destination = Self.uniqueDestination(for: directory.appendingPathComponent(name))
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            } catch {
                throw FileSystemError.cannotCreateFolder(name, underlying: error)
            }
            return destination
        }.value
    }

    /// Creates a new empty file in `directory`, auto-numbering ("New File",
    /// "New File (2)", …) if `name` is already taken.
    @discardableResult
    func createFile(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let destination = Self.uniqueDestination(for: directory.appendingPathComponent(name))
            do {
                try Data().write(to: destination, options: .withoutOverwriting)
            } catch {
                throw FileSystemError.cannotCreateFile(name, underlying: error)
            }
            return destination
        }.value
    }

    @discardableResult
    func rename(_ url: URL, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw FileSystemError.alreadyExists(newName)
            }
            do {
                try FileManager.default.moveItem(at: url, to: destination)
            } catch {
                throw FileSystemError.cannotRename(newName, underlying: error)
            }
            return destination
        }.value
    }

    /// The closest folder above `url` that still exists — where a tab goes
    /// when its folder disappears, so it stays inside the same project or
    /// Workspace. `nil` when all that's left is `/` or `/Volumes` (an
    /// ejected drive or a dropped share), where home is the better landing.
    func nearestExistingFolder(above url: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            var candidate = url.standardizedFileURL
            while candidate.pathComponents.count > 1 {
                candidate = candidate.deletingLastPathComponent()
                if ["/", "/Volumes"].contains(candidate.path) { return nil }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return candidate
                }
            }
            return nil
        }.value
    }

    /// Returns where each original URL actually landed in Trash (its name
    /// may have been de-duplicated) — callers use this to remember the
    /// original location for a later Restore, since macOS doesn't record
    /// that anywhere a third-party app can read (Finder's own "Put Back"
    /// is private, Finder-only bookkeeping).
    @discardableResult
    /// Trashes each of `urls`, going on past any that can't be — so one
    /// protected item doesn't leave the rest behind, and the ones that did
    /// go are still known (for Undo and Put Back).
    func moveToTrash(_ urls: [URL]) async -> TrashResult {
        let trashItem = self.trashItem
        return await Task.detached(priority: .userInitiated) {
            var result = TrashResult()
            for url in urls {
                do {
                    let trashedURL = try trashItem(url)
                    result.trashed.append(url)
                    if let trashedURL {
                        result.locations[url] = trashedURL
                    }
                } catch {
                    result.failures.append((url, FileSystemError.cannotTrash(url, underlying: error)))
                }
            }
            return result
        }.value
    }

    /// Makes a Finder alias to each of `urls` in `directory`, named like
    /// Finder's: "name alias", then "name alias 2", … when that's taken.
    /// Returns the aliases made, in order; stops at the first failure.
    func makeAliases(to urls: [URL], in directory: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            var made: [URL] = []
            for url in urls {
                let alias = Self.aliasDestination(for: url, in: directory)
                do {
                    try Platform.makeAlias(to: url, at: alias)
                } catch {
                    throw FileSystemError.cannotMakeAlias(url.lastPathComponent, underlying: error)
                }
                made.append(alias)
            }
            return made
        }.value
    }

    static func aliasDestination(for url: URL, in directory: URL) -> URL {
        let base = "\(url.lastPathComponent) alias"
        var candidate = directory.appendingPathComponent(base)
        var counter = 2
        while (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil {
            candidate = directory.appendingPathComponent("\(base) \(counter)")
            counter += 1
        }
        return candidate
    }

    /// Moves an item out of Trash back to `destination`.
    func restoreFromTrash(_ trashedURL: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.moveItem(at: trashedURL, to: destination)
            } catch {
                throw FileSystemError.cannotRestore(trashedURL, underlying: error)
            }
        }.value
    }

    /// Permanently deletes — no Trash involved. Used for "Delete
    /// Immediately" and "Empty Trash".
    func deletePermanently(_ urls: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            for url in urls {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    // A trashed folder can hold read-only subfolders (Go's
                    // module cache, some build output): unlinking inside one
                    // is refused. Make the folders ours to change and retry,
                    // as a file manager's Empty Trash does.
                    if Self.isPermissionDenied(error), Self.makeFoldersWritable(under: url) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            continue
                        } catch {
                            throw FileSystemError.cannotDeletePermanently(url, underlying: error)
                        }
                    }
                    throw FileSystemError.cannotDeletePermanently(url, underlying: error)
                }
            }
        }.value
    }

    private nonisolated static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError
        }
        return nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EACCES) || nsError.code == Int(EPERM))
    }

    /// Gives the owner read, write and search on every folder in the tree at
    /// `url` (symlinks are not followed). Returns whether it changed any.
    @discardableResult
    nonisolated static func makeFoldersWritable(under url: URL) -> Bool {
        let manager = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        var changed = false
        if let mode = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber,
           mode.intValue & 0o700 != 0o700 {
            changed = (try? manager.setAttributes([.posixPermissions: mode.intValue | 0o700], ofItemAtPath: url.path)) != nil
        }
        let children = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        for child in children where makeFoldersWritable(under: child) { changed = true }
        return changed
    }

    /// Recursive byte total for `url` — 0 for anything unreadable along the
    /// way rather than aborting, same tolerant-of-errors shape
    /// `SearchService` already uses for its own tree walk.
    private static func size(of url: URL, cancellation: CancellationFlag? = nil) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if cancellation?.isCancelled == true { break } // caller checks the flag itself
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Total recursive byte size of `urls` combined — used to size a
    /// progress bar before starting a copy/move.
    func totalSize(of urls: [URL]) async -> Int64 {
        await Task.detached(priority: .utility) {
            urls.reduce(into: Int64(0)) { $0 += Self.size(of: $1) }
        }.value
    }

    /// Copies each of `urls` into `destinationDirectory`. Name collisions
    /// are found before anything is copied and handed to
    /// `resolveConflicts` all at once (awaited back on whatever actor
    /// called `copyItems` — typically the main actor — so the UI can
    /// prompt the user); a collision that only appears once the copy is
    /// under way is asked about on its own. `.cancel` up front copies
    /// nothing; partway through it stops like the progress popup's Cancel.
    /// Replace moves the item it replaces to the Trash (see `replace`).
    /// Reports a Finder-style
    /// progress popup via `FileOperationProgressCenter` — same direct
    /// dependency on a shared, UI-adjacent-but-not-SwiftUI singleton
    /// `ArchiveService` already has with `ArchiveProcessRegistry`. Progress
    /// is byte-level, within files too, and the popup's Cancel stops the
    /// copy mid-file (see `FileCopier`); a cancel or failure removes the
    /// half-copied item and throws, `CancellationError` for a cancel.
    ///
    /// Each item that completes is appended to `changeLog` (if given) as it
    /// finishes — so Undo can still cover the items that made it when the
    /// operation as a whole fails or is cancelled partway through.
    func copyItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        changeLog: FileChangeLog? = nil,
        resolveConflicts: @escaping (FileConflictRequest) async -> FileConflictAnswer,
        nameFixes: [URL: String] = [:],
        skipping: Set<URL> = [],
        retry: (@MainActor @Sendable ([URL]) -> Void)? = nil
    ) async throws {
        try await performFileOperation(urls, to: destinationDirectory, isMove: false, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: nameFixes, skipping: skipping, retry: retry) { url, destination, context in
            do {
                try Platform.copyItem(url, to: destination, includeMetadata: context.includeMetadata, cancellation: context.cancellation, onProgress: context.onProgress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FileSystemError.cannotCopy(url.lastPathComponent, underlying: error)
            }
            try Self.verifyIfAsked(url, copiedTo: destination, context)
        }
    }

    /// Moves each of `urls` into `destinationDirectory` (used for Cut+Paste).
    /// Conflict handling, progress reporting, and `changeLog` match
    /// `copyItems`. A move within one volume is just a rename (instant); to
    /// another volume it's a copy with progress, then deleting the source —
    /// only once the copy has fully succeeded.
    func moveItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        changeLog: FileChangeLog? = nil,
        resolveConflicts: @escaping (FileConflictRequest) async -> FileConflictAnswer,
        nameFixes: [URL: String] = [:],
        skipping: Set<URL> = [],
        retry: (@MainActor @Sendable ([URL]) -> Void)? = nil
    ) async throws {
        try await performFileOperation(urls, to: destinationDirectory, isMove: true, changeLog: changeLog, resolveConflicts: resolveConflicts, nameFixes: nameFixes, skipping: skipping, retry: retry) { url, destination, context in
            if Self.isSameVolume(url, destination.deletingLastPathComponent()) {
                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                } catch {
                    throw FileSystemError.cannotMove(url.lastPathComponent, underlying: error)
                }
                return
            }
            do {
                try Platform.copyItem(url, to: destination, includeMetadata: context.includeMetadata, cancellation: context.cancellation, onProgress: context.onProgress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FileSystemError.cannotMove(url.lastPathComponent, underlying: error)
            }
            // The original is only deleted once its copy has checked out.
            try Self.verifyIfAsked(url, copiedTo: destination, context)
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw FileSystemError.cannotMove(url.lastPathComponent, underlying: error)
            }
        }
    }

    /// `copyItems` asking about each collision on its own, by name.
    func copyItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        changeLog: FileChangeLog? = nil,
        onConflict: @escaping (String) async -> FileConflictResolution,
        retry: (@MainActor @Sendable ([URL]) -> Void)? = nil
    ) async throws {
        try await copyItems(urls, to: destinationDirectory, changeLog: changeLog, resolveConflicts: Self.oneAtATime(onConflict), retry: retry)
    }

    /// `moveItems` asking about each collision on its own, by name.
    func moveItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        changeLog: FileChangeLog? = nil,
        onConflict: @escaping (String) async -> FileConflictResolution,
        retry: (@MainActor @Sendable ([URL]) -> Void)? = nil
    ) async throws {
        try await moveItems(urls, to: destinationDirectory, changeLog: changeLog, resolveConflicts: Self.oneAtATime(onConflict), retry: retry)
    }

    private static func oneAtATime(
        _ onConflict: @escaping (String) async -> FileConflictResolution
    ) -> (FileConflictRequest) async -> FileConflictAnswer {
        { request in
            var answers: [URL: FileConflictResolution] = [:]
            for conflict in request.conflicts {
                answers[conflict.source] = await onConflict(conflict.name)
            }
            return .resolve(answers)
        }
    }

    /// The items in `urls` whose name is already taken in
    /// `destinationDirectory` by a *different* item — see `placement` for
    /// why an item's own folder doesn't count. Reads metadata from disk;
    /// call off the main thread.
    static func conflicts(for urls: [URL], in destinationDirectory: URL) -> [FileConflictItem] {
        urls.compactMap { url in
            let destination = destinationDirectory.appendingPathComponent(url.lastPathComponent)
            guard FileManager.default.fileExists(atPath: destination.path),
                  !isSameDirectory(url.deletingLastPathComponent(), destinationDirectory) else { return nil }
            return FileConflictItem(source: url, existing: destination)
        }
    }

    /// What one item's copy/move gets to work with.
    struct ItemContext {
        let cancellation: CancellationFlag
        /// Bytes done of this item.
        let onProgress: (Int64) -> Void
        /// Verify copies is on.
        let verify: Bool
        /// Check copies within one disk too (tests).
        let verifySameDisk: Bool
        /// Copy extended attributes and ACLs (false for NFS shares, unless
        /// the setting says otherwise).
        let includeMetadata: Bool
        /// Shows "Verifying the copy…" while true.
        let onVerifying: (Bool) -> Void
    }

    /// Copies/moves one item: (source, destination, context).
    private typealias ItemOperation = (URL, URL, ItemContext) throws -> Void

    /// With Verify copies on, checks a copy that crossed to another disk
    /// against its original; a copy that doesn't match is removed (it's
    /// ours, just made) and the item fails. Copies within one disk aren't
    /// checked: they're clones sharing the original's data.
    private static func verifyIfAsked(_ original: URL, copiedTo copy: URL, _ context: ItemContext) throws {
        guard context.verify, context.verifySameDisk || !isSameVolume(original, copy.deletingLastPathComponent()) else { return }
        context.onVerifying(true)
        defer { context.onVerifying(false) }
        do {
            try FileVerifier.verify(original, matches: copy, cancellation: context.cancellation)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    /// Shared body of `copyItems`/`moveItems`: resolve conflicts, run
    /// `perform` for each item off the main thread, and drive a
    /// `FileOperationProgressCenter` entry around the whole thing. When it
    /// fails, the record's Retry calls `retry` with the items that hadn't
    /// finished (not ones the user chose to skip).
    private func performFileOperation(
        _ urls: [URL],
        to destinationDirectory: URL,
        isMove: Bool,
        changeLog: FileChangeLog?,
        resolveConflicts: @escaping (FileConflictRequest) async -> FileConflictAnswer,
        nameFixes: [URL: String],
        skipping: Set<URL>,
        retry: (@MainActor @Sendable ([URL]) -> Void)?,
        perform: @escaping ItemOperation
    ) async throws {
        // Folders with a renamed or skipped item somewhere inside are copied
        // item by item (see `transfer`), since a whole-folder copy can't
        // rename or leave out what's in it.
        // By path: the same folder's URL can differ by a trailing slash.
        let itemByItem = Set(Self.foldersContaining(Array(nameFixes.keys) + Array(skipping), within: urls).map(\.standardizedFileURL.path))
        let fixedNames = Dictionary(nameFixes.map { ($0.key.standardizedFileURL.path, $0.value) }, uniquingKeysWith: { first, _ in first })
        let skippedPaths = Set(skipping.map(\.standardizedFileURL.path))
        guard !urls.isEmpty else { return }
        // Checked up front, before anything is touched, so a bad request
        // fails cleanly instead of partway through a multi-item operation.
        for url in urls where Self.isPath(Self.canonicalPath(destinationDirectory), inside: Self.itemPath(url), orEqual: true) {
            throw FileSystemError.cannotPlaceInsideItself(url.lastPathComponent)
        }

        // Every collision asked about at once, before the progress popup
        // goes up — so a 100-item paste is one question, not 100 spread
        // through the copy.
        let conflicts = await Task.detached(priority: .userInitiated) {
            Self.conflicts(for: urls, in: destinationDirectory)
        }.value
        var decisions: [URL: FileConflictResolution] = [:]
        if !conflicts.isEmpty {
            let request = FileConflictRequest(conflicts: conflicts, itemCount: urls.count, destination: destinationDirectory, isMove: isMove)
            switch await resolveConflicts(request) {
            case .cancel: return
            case .resolve(let answers): decisions = answers
            }
        }
        let trashItem = self.trashItem
        let verb = isMove ? "Moving" : "Copying"
        let destinationName = FileManager.default.displayName(atPath: destinationDirectory.path)
        let title = urls.count == 1
            ? "\(verb) \u{201C}\(urls[0].lastPathComponent)\u{201D} to \u{201C}\(destinationName)\u{201D}"
            : "\(verb) \(urls.count) items to \u{201C}\(destinationName)\u{201D}"

        // The popup goes up right away, "Preparing…", while sizing a big
        // folder (which can take a while on its own) — and Cancel works
        // from that moment on.
        let cancellation = CancellationFlag()
        let startNowFlag = StartNowFlag()
        let parents = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        let progress = self.progress
        let progressID = await progress().begin(
            title: title,
            symbolName: "folder.fill",
            totalBytes: 0,
            isPreparing: true,
            sourceFolder: parents.count == 1 ? parents.first : nil,
            destinationFolder: destinationDirectory,
            itemCount: urls.count,
            pauseControl: cancellation,
            startNow: { startNowFlag.set() },
            cancel: { cancellation.cancel() }
        )
        let reporter = ProgressReporter(id: progressID, reporter: progress)
        let verify = verifiesCopies()
        let verifySameDisk = verifiesSameDiskCopies
        let includeMetadata = keepsMetadataOnShares() || storesMetadataNatively(destinationDirectory)
        let itemContext: (@escaping (Int64) -> Void) -> ItemContext = { onProgress in
            ItemContext(cancellation: cancellation, onProgress: onProgress, verify: verify, verifySameDisk: verifySameDisk, includeMetadata: includeMetadata) { isVerifying in
                Task { @MainActor in progress().setVerifying(progressID, isVerifying) }
            }
        }
        // One at a time per disk: data moving between disks waits for any
        // earlier copy using one of them (see `FileTransferQueue`).
        let queue = transferQueue
        let disks = queuesTransfers() ? FileTransferQueue.disks(for: urls, into: destinationDirectory) : []

        // Not a plain `defer` — see `ArchiveService.withProgress`'s
        // comment on the same pattern: `defer { Task { await ... } }`
        // only *schedules* the cleanup, it doesn't guarantee it has run by
        // the time this function returns.
        /// Copies/moves one item into `directory` as its placement says,
        /// recording the change. `base` is the bytes done before it, for
        /// progress. Merge recurses into the folder's contents.
        func transfer(_ url: URL, into directory: URL, itemCount: Int, decision: FileConflictResolution?, base: Int64) async throws {
            let path = url.standardizedFileURL.path
            if skippedPaths.contains(path) { return }
            let name = fixedNames[path] ?? url.lastPathComponent
            if itemByItem.contains(path) {
                // Made here, then filled item by item.
                let folder = directory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: folder.path) {
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                    } catch {
                        throw FileSystemError.cannotCreateFolder(name, underlying: error)
                    }
                    changeLog?.append(.created(folder))
                }
                try await mergeContents(of: url, into: folder, base: base)
                return
            }
            // A collision nobody was asked about (something appeared there
            // since, or two items with the same name from different
            // folders) gets its own question.
            let placement = try await Self.placement(for: url, named: name, in: directory, isMove: isMove, decision: decision) { conflict in
                await resolveConflicts(FileConflictRequest(conflicts: [conflict], itemCount: itemCount, destination: directory, isMove: isMove))
            }
            let onProgress: (Int64) -> Void = { reporter.report(base + $0) }
            let destination: URL
            switch placement {
            case .skip:
                return
            case .merge(let existingFolder):
                try await mergeContents(of: url, into: existingFolder, base: base)
                return
            case .place(let placed):
                destination = placed
                try await Task.detached(priority: .userInitiated) {
                    try perform(url, destination, itemContext(onProgress))
                }.value
            case .replace(let replaced):
                destination = replaced
                let trashedAt = try await Task.detached(priority: .userInitiated) {
                    try Self.replace(destination, with: url, trashItem: trashItem) { source, staged in
                        try perform(source, staged, itemContext(onProgress))
                    }
                }.value
                // Recorded before the new item, so Undo takes the new
                // one away first and then puts the old one back.
                if let trashedAt {
                    changeLog?.append(.trashed(original: destination, trashedAt: trashedAt))
                }
            }
            changeLog?.append(isMove ? .moved(from: url, to: destination) : .created(destination))
        }

        /// Merge: `source`'s contents go into `existingFolder` one by one,
        /// with the same up-front question for anything already there (and
        /// Merge again for folders inside). A move then sends the emptied
        /// source folder to the Trash, so Undo can put everything back.
        func mergeContents(of source: URL, into existingFolder: URL, base: Int64) async throws {
            let children = try await Task.detached(priority: .userInitiated) {
                try Self.mergeableContents(of: source)
            }.value
            let conflicts = await Task.detached(priority: .userInitiated) {
                Self.conflicts(for: children, in: existingFolder)
            }.value
            var childDecisions: [URL: FileConflictResolution] = [:]
            if !conflicts.isEmpty {
                let request = FileConflictRequest(conflicts: conflicts, itemCount: children.count, destination: existingFolder, isMove: isMove)
                switch await resolveConflicts(request) {
                case .cancel: throw CancellationError()
                case .resolve(let answers): childDecisions = answers
                }
            }
            var done: Int64 = 0
            for child in children {
                if cancellation.isPaused {
                    await Task.detached(priority: .userInitiated) { cancellation.waitWhilePaused() }.value
                }
                if cancellation.isCancelled { throw CancellationError() }
                try Task.checkCancellation()
                let size = await Task.detached(priority: .utility) { Self.size(of: child, cancellation: cancellation) }.value
                try await transfer(child, into: existingFolder, itemCount: children.count, decision: childDecisions[child], base: base + done)
                done += size
                reporter.report(base + done, force: true)
            }
            if isMove, let emptied = try? Self.mergeableContents(of: source), emptied.isEmpty {
                // Only Finder's view settings left (or nothing): the folder
                // itself has moved. Left alone where there's no Trash.
                if let trashedAt = try? trashItem(source) {
                    changeLog?.append(.trashed(original: source, trashedAt: trashedAt))
                }
            }
        }

        // Items done with — copied, moved, or skipped — so a Retry only
        // does the rest.
        var finishedCount = 0
        do {
            if !disks.isEmpty {
                try await queue.acquire(
                    id: progressID,
                    disks: disks,
                    shouldStop: { cancellation.isCancelled },
                    startNow: { startNowFlag.isSet },
                    onWaiting: { await progress().setWaiting(progressID, true) }
                )
                await progress().setWaiting(progressID, false)
            }
            let itemSizes = await Task.detached(priority: .utility) {
                urls.map { Self.size(of: $0, cancellation: cancellation) }
            }.value
            if cancellation.isCancelled { throw CancellationError() }
            await progress().startTransfer(progressID, totalBytes: itemSizes.reduce(0, +))

            var completedBytes: Int64 = 0
            for (index, url) in urls.enumerated() {
                // Paused between items (a same-volume move is a rename,
                // with no copying to pause inside).
                if cancellation.isPaused {
                    await Task.detached(priority: .userInitiated) { cancellation.waitWhilePaused() }.value
                }
                if cancellation.isCancelled { throw CancellationError() }
                try Task.checkCancellation()
                await progress().setCurrentItem(progressID, index: index, name: url.lastPathComponent)
                try await transfer(url, into: destinationDirectory, itemCount: urls.count, decision: decisions[url], base: completedBytes)

                completedBytes += itemSizes[index]
                reporter.report(completedBytes, force: true)
                finishedCount = index + 1
            }
            await queue.release(id: progressID)
            await progress().finish(progressID)
        } catch is CancellationError {
            await queue.release(id: progressID)
            await progress().finish(progressID, outcome: .cancelled, finishedItems: finishedCount)
            throw CancellationError()
        } catch {
            await queue.release(id: progressID)
            let remaining = Array(urls[finishedCount...])
            await progress().finish(
                progressID,
                outcome: .failure(error, finished: finishedCount, of: urls.count),
                finishedItems: finishedCount,
                retry: retry.map { retry in { @MainActor in retry(remaining) } }
            )
            throw error
        }
    }

    /// The folders among `items`' ancestors that are one of `tops` or
    /// inside one — never anything above what was chosen.
    static func foldersContaining(_ items: [URL], within tops: [URL]) -> Set<URL> {
        let topPaths = tops.map(\.standardizedFileURL.path)
        var folders: Set<URL> = []
        for item in items {
            let path = item.standardizedFileURL.path
            guard let top = topPaths.first(where: { path.hasPrefix($0 + "/") }) else { continue }
            var parent = item.deletingLastPathComponent()
            while parent.standardizedFileURL.path.count >= top.count {
                folders.insert(parent)
                parent = parent.deletingLastPathComponent()
            }
        }
        return folders
    }

    /// Whether `a` and `b` are on the same volume — a move between them is
    /// then a rename rather than a copy.
    private static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let idA = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let idB = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return false // unknown: copy-then-delete is the safe way round
        }
        return idA.isEqual(idB)
    }

    /// Where (and how) to copy/move one item.
    private enum Placement {
        case skip
        /// Nothing is in the way — copy/move straight to this URL.
        case place(URL)
        /// An existing item at this URL should be swapped out — see `replace`.
        case replace(URL)
        /// An existing folder at this URL takes the source folder's contents.
        case merge(URL)
    }

    /// Decides where `url` goes in `destinationDirectory`, using the
    /// up-front `decision` for a genuine collision with a *different* item
    /// (or `askAgain` when there wasn't one).
    /// Pasting or dropping an item back into the folder it's already in
    /// isn't a conflict at all: a copy duplicates it as "name (2)", like
    /// Finder's "name copy", and a move is a no-op. Offering Replace there
    /// used to delete the original before copying it onto itself.
    private static func placement(
        for url: URL,
        named name: String? = nil,
        in destinationDirectory: URL,
        isMove: Bool,
        decision: FileConflictResolution?,
        askAgain: (FileConflictItem) async -> FileConflictAnswer
    ) async throws -> Placement {
        let destination = destinationDirectory.appendingPathComponent(name ?? url.lastPathComponent)
        guard FileManager.default.fileExists(atPath: destination.path) else { return .place(destination) }

        if isSameDirectory(url.deletingLastPathComponent(), destinationDirectory) {
            return isMove ? .skip : .place(uniqueDestination(for: destination))
        }

        let resolution: FileConflictResolution
        if let decision {
            resolution = decision
        } else {
            switch await askAgain(FileConflictItem(source: url, existing: destination)) {
            case .cancel: throw CancellationError()
            case .resolve(let answers): resolution = answers[url] ?? .skip
            }
        }

        switch resolution {
        case .skip:
            return .skip
        case .replace:
            // Replacing a folder that holds the source would take the
            // source down with it — Finder refuses this too.
            guard !isPath(itemPath(url), inside: itemPath(destination), orEqual: false) else {
                throw FileSystemError.cannotReplaceContainingItem(destination.lastPathComponent)
            }
            return .replace(destination)
        case .keepBoth:
            return .place(uniqueDestination(for: destination))
        case .merge:
            // Only folder into folder (not packages); anything else that
            // gets here is skipped rather than guessed at.
            guard FileConflictItem.Metadata.read(url).isMergeableFolder,
                  FileConflictItem.Metadata.read(destination).isMergeableFolder else { return .skip }
            return .merge(destination)
        }
    }

    /// A folder's contents for a merge — hidden files included (they're
    /// part of the folder), but not Finder's `.DS_Store` view settings,
    /// which would otherwise turn up as a conflict in nearly every merge.
    static func mergeableContents(of folder: URL) throws -> [URL] {
        do {
            // Built from `folder` rather than taken from the listing, which
            // resolves symlinks (`/var` → `/private/var`), so the change log
            // and Undo keep the paths the caller used.
            return try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0 != ".DS_Store" }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { folder.appendingPathComponent($0) }
        } catch {
            throw FileSystemError.cannotList(folder, underlying: error)
        }
    }

    /// Replaces the existing item at `destination` with `source` without
    /// ever leaving the user with neither, and returns where the old item
    /// went in the Trash. The new item is copied/moved to a hidden staging
    /// name beside `destination` first; only once that has fully succeeded
    /// is the old item moved to the Trash and the new one renamed into
    /// place. If that rename fails, the old item comes back out of the
    /// Trash. On a volume with no Trash (most network shares) the old item
    /// is renamed aside instead and deleted once the new one is in place —
    /// what Replace always did — and the result is `nil`.
    private static func replace(
        _ destination: URL,
        with source: URL,
        trashItem: (URL) throws -> URL?,
        using perform: (URL, URL) throws -> Void
    ) throws -> URL? {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let name = destination.lastPathComponent
        let stagedNew = directory.appendingPathComponent(".\(name).oneroot-new-\(UUID().uuidString)")

        do {
            try perform(source, stagedNew)
        } catch {
            try? fileManager.removeItem(at: stagedNew) // partial copy, ours to discard
            throw error
        }

        var trashedAt: URL?
        var stagedOld: URL?
        if let trashed = try? trashItem(destination) {
            trashedAt = trashed
        } else if !fileManager.fileExists(atPath: destination.path) {
            // Trashed, but the Trash didn't say where: carry on without
            // Undo for the old item rather than fail a finished copy.
        } else {
            let aside = directory.appendingPathComponent(".\(name).oneroot-old-\(UUID().uuidString)")
            do {
                try fileManager.moveItem(at: destination, to: aside)
            } catch {
                try? fileManager.removeItem(at: stagedNew)
                throw FileSystemError.cannotReplace(name, underlying: error)
            }
            stagedOld = aside
        }

        do {
            try fileManager.moveItem(at: stagedNew, to: destination)
        } catch {
            if let previous = trashedAt ?? stagedOld {
                try? fileManager.moveItem(at: previous, to: destination)
            }
            try? fileManager.removeItem(at: stagedNew)
            throw FileSystemError.cannotReplace(name, underlying: error)
        }

        // The replacement is in place; failing to clean up the old copy
        // only leaves a hidden leftover, not a failed operation.
        if let stagedOld { try? fileManager.removeItem(at: stagedOld) }
        return trashedAt
    }

    /// Whether two directory URLs name the same folder, even when they're
    /// spelled differently (symlinked parents like `/var` → `/private/var`,
    /// or different letter case on a case-insensitive volume).
    private static func isSameDirectory(_ a: URL, _ b: URL) -> Bool {
        if canonicalPath(a) == canonicalPath(b) { return true }
        guard let idA = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let idB = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else {
            return false
        }
        return idA.isEqual(idB)
    }

    /// Whether `path` is inside `container` (or is `container` itself, when
    /// `orEqual`) — e.g. pasting a folder into one of its own subfolders.
    private static func isPath(_ path: String, inside container: String, orEqual: Bool) -> Bool {
        (orEqual && path == container) || path.hasPrefix(container + "/")
    }

    /// Fully resolved path — for a directory something is being put into.
    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Path of the item itself, with only its parent resolved — so a
    /// symlink being copied is treated as the link, not what it points to.
    private static func itemPath(_ url: URL) -> String {
        canonicalPath(url.deletingLastPathComponent()) + "/" + url.lastPathComponent
    }

    /// Appends " (2)", " (3)", … until the path doesn't collide with an
    /// existing item (Windows Explorer-style, matching this app's design).
    /// Internal rather than private so `ArchiveService` can reuse the same
    /// naming scheme for archive output/extraction-folder collisions.
    static func uniqueDestination(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let baseName = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent

        var counter = 2
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// Flat view (#66): every file under `folder`, subfolders included —
    /// not the folders themselves, and not what's inside packages (an app
    /// is one item). Delivered in batches through `onBatch` as the walk
    /// goes, so a big tree fills in instead of hanging; stops at `limit`
    /// files and returns whether it did. Unreadable folders are skipped.
    func listAllFiles(
        under folder: URL,
        includeHidden: Bool,
        limit: Int = FileSystemService.flatViewLimit,
        onBatch: @escaping @Sendable ([FileNode]) async -> Void
    ) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !includeHidden { options.insert(.skipsHiddenFiles) }
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: Self.resourceKeys,
                options: options,
                errorHandler: { _, _ in true }
            ) else { return false }
            var batch: [FileNode] = []
            var count = 0
            var lastSent = Date()
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let node = Self.makeNode(for: url)
                if node.isDirectory && !node.isPackage { continue }
                batch.append(node)
                count += 1
                if count >= limit {
                    await onBatch(batch)
                    return true
                }
                if batch.count >= 500 || Date().timeIntervalSince(lastSent) > 0.3 {
                    await onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                    lastSent = Date()
                }
            }
            await onBatch(batch)
            return false
        }.value
    }

    /// The most files the flat view lists at once.
    static let flatViewLimit = 50_000

    static func makeNode(for url: URL) -> FileNode {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        return FileNode(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            isDirectory: values?.isDirectory ?? false,
            isPackage: Platform.hasPackages && (values?.isPackage ?? false),
            size: values?.fileSize.map(Int64.init),
            modificationDate: values?.contentModificationDate,
            kind: Platform.kind(of: url, values: values),
            creationDate: values?.creationDate,
            dateAdded: values?.addedToDirectoryDate,
            lastOpenedDate: values?.contentAccessDate,
            tags: Platform.listedTags(of: url, values: values)
        )
    }

    private static func byFolderThenName(_ a: FileNode, _ b: FileNode) -> Bool {
        if a.isDirectory != b.isDirectory {
            return a.isDirectory
        }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
