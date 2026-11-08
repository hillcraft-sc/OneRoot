#if os(macOS) // macOS only; the Linux side is LinuxPlatform.swift (#79)
import CoreServices
import Foundation

/// Runs Spotlight queries with the C `MDQuery` API, kept contained here.
/// Synchronous on purpose: callers already run off the main actor, and
/// `NSMetadataQuery`'s asynchronous mode needs a run loop on the calling
/// thread, which a background task doesn't have.
struct SpotlightIndex: SearchIndexQuerying, RecentItemsQuerying {
    /// When `path` was last opened, as Spotlight records it (Finder's Date
    /// Last Opened). `nil` if never, or if Spotlight doesn't know the item.
    static func lastUsedDate(atPath path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    func recentlyUsed(withinDays days: Int, under roots: [URL]) -> [(path: String, lastUsed: Date)] {
        let queryString = "kMDItemLastUsedDate >= $time.today(-\(days))"
        guard !roots.isEmpty, let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, roots.map(\.path) as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var found: [(path: String, lastUsed: Date)] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            else { continue }
            found.append((path, date))
        }
        return found
    }

    func paths(matching query: String, under root: URL) -> [String]? {
        let scope = root.path
        guard isIndexed(scope) else { return nil }
        return run(query, scope: scope, maxCount: nil)
    }

    /// Spotlight can't tell "no matches" from "this folder isn't indexed"
    /// (network shares, drives with indexing turned off), so ask it for
    /// any one item under `scope`. Nothing back from a folder that does
    /// have visible contents means it isn't indexed.
    private func isIndexed(_ scope: String) -> Bool {
        // Not `kMDItemFSName == "*"` — a bare wildcard matches nothing.
        guard let probe = run("kMDItemContentTypeTree == \"public.item\"", scope: scope, maxCount: 1) else { return false }
        if !probe.isEmpty { return true }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: scope)) ?? []
        return !contents.contains { !$0.hasPrefix(".") }
    }

    private func run(_ queryString: String, scope: String, maxCount: Int?) -> [String]? {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            return nil // a malformed query string
        }
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        if let maxCount {
            MDQuerySetMaxCount(query, maxCount)
        }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return nil }

        let count = MDQueryGetResultCount(query)
        var paths: [String] = []
        paths.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                paths.append(path)
            }
        }
        return paths
    }
}
#endif
