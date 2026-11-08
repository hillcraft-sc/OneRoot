import Foundation

/// Adds up what a folder holds, everything inside it included, for
/// Visualize. UI-agnostic and off the main thread; reports as it goes (a
/// few times a second) and stops promptly when the stream's consumer goes
/// away or its task is cancelled.
///
/// Safe on awkward trees: symbolic links aren't followed; a package (an
/// app, a Photos library) counts as one item of its own kind; unreadable
/// folders are counted and skipped; cloud placeholders are read without
/// downloading anything.
struct StorageScanner {
    /// How often a partial report is sent.
    var reportInterval: TimeInterval = 0.3

    func scan(_ root: URL, now: Date = Date()) -> AsyncThrowingStream<StorageReport, Error> {
        AsyncThrowingStream { continuation in
            let cancellation = CancellationFlag()
            let interval = reportInterval
            let task = Task.detached(priority: .utility) {
                do {
                    let report = try Self.walk(root, now: now, interval: interval, cancellation: cancellation) { partial in
                        continuation.yield(partial)
                    }
                    continuation.yield(report)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                cancellation.cancel()
                task.cancel()
            }
        }
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey,
        .fileSizeKey, .contentModificationDateKey,
        .isUbiquitousItemKey,
    ] + Platform.fileTypeKeys

    static func walk(
        _ root: URL,
        now: Date,
        interval: TimeInterval,
        cancellation: CancellationFlag,
        onProgress: (StorageReport) -> Void
    ) throws -> StorageReport {
        var report = StorageReport(root: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }
        var unreadable = 0
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: root.path])
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count
        var children: [URL: StorageEntry] = [:]
        /// Packages being walked, outermost first. Everything inside one
        /// adds to it, and it's counted as a single item once it's done.
        var packages: [PackageWalk] = []
        var lastReport = Date()
        var visited = 0

        func finishPackage(_ package: PackageWalk) {
            let file = StorageFile(url: package.url, size: package.size)
            report.categories[package.category, default: StorageBucket()].add(file)
            report.ages[StorageAge.of(package.modified, now: now), default: StorageBucket()].add(file)
            if package.tags.isEmpty {
                report.untagged.add(file)
            } else {
                for tag in package.tags { report.tags[tag, default: StorageBucket()].add(file) }
            }
            report.cloud[package.cloudState, default: StorageBucket()].add(file)
        }

        for case let url as URL in enumerator {
            visited += 1
            if visited % 200 == 0 {
                if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
                if Date().timeIntervalSince(lastReport) >= interval {
                    lastReport = Date()
                    report.unreadableCount = unreadable
                    report.children = sortedChildren(children)
                    onProgress(report)
                }
            }
            let level = enumerator.level
            while let last = packages.last, last.level >= level {
                packages.removeLast()
                // Only the outermost is counted; an inner one adds to it.
                if packages.isEmpty { finishPackage(last) }
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                unreadable += 1
                continue
            }
            if values.isSymbolicLink == true { continue }

            // The scanned folder's own item this is in (or is).
            let components = url.standardizedFileURL.pathComponents
            guard components.count > rootDepth else { continue }
            let childURL = root.appendingPathComponent(components[rootDepth])

            if values.isDirectory == true {
                if level == 1 {
                    children[childURL] = StorageEntry(url: childURL, isDirectory: true, size: 0, fileCount: 0)
                }
                if Platform.hasPackages, values.isPackage == true {
                    packages.append(PackageWalk(
                        level: level,
                        url: url,
                        category: Platform.storageCategory(of: url, values: values),
                        modified: values.contentModificationDate,
                        tags: tags(of: url),
                        cloudState: cloudState(url, values)
                    ))
                } else if packages.isEmpty {
                    report.folderCount += 1
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.fileSize ?? 0)
            report.totalSize += size
            report.fileCount += 1
            if level == 1 {
                children[childURL] = StorageEntry(url: childURL, isDirectory: false, size: size, fileCount: 1)
            } else {
                children[childURL, default: StorageEntry(url: childURL, isDirectory: true, size: 0, fileCount: 0)].size += size
                children[childURL]?.fileCount += 1
            }
            if !packages.isEmpty {
                packages[0].size += size
                continue
            }

            let file = StorageFile(url: url, size: size)
            report.categories[Platform.storageCategory(of: url, values: values), default: StorageBucket()].add(file)
            report.ages[StorageAge.of(values.contentModificationDate, now: now), default: StorageBucket()].add(file)
            let tags = tags(of: url)
            if tags.isEmpty {
                report.untagged.add(file)
            } else {
                for tag in tags { report.tags[tag, default: StorageBucket()].add(file) }
            }
            report.cloud[cloudState(url, values), default: StorageBucket()].add(file)
        }
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
        if let outermost = packages.first { finishPackage(outermost) }

        report.unreadableCount = unreadable
        report.children = sortedChildren(children)
        report.scannedAt = now
        report.isComplete = true
        return report
    }

    private struct PackageWalk {
        let level: Int
        let url: URL
        let category: StorageCategory
        let modified: Date?
        let tags: [String]
        let cloudState: StorageCloudState
        var size: Int64 = 0
    }

    /// Read on its own rather than prefetched with the rest: a directory
    /// listing's tags can lag behind a change just made.
    private static func tags(of url: URL) -> [String] {
        (try? Platform.tags(of: url)) ?? []
    }

    /// Cloud-only when the system holds just a placeholder; downloaded when
    /// a provider syncs it and it's here.
    private static func cloudState(_ url: URL, _ values: URLResourceValues) -> StorageCloudState {
        if SearchService.fileIsDataless(url) { return .cloudOnly }
        return values.isUbiquitousItem == true ? .downloaded : .notInCloud
    }

    private static func sortedChildren(_ children: [URL: StorageEntry]) -> [StorageEntry] {
        children.values.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
