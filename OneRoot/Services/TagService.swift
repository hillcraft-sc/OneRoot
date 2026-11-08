import Foundation

/// Reads and writes Finder tags. A tag is just a name: the standard ones
/// (Red, Orange, …) show in their colors in Finder and OneRoot, a custom
/// one in Finder's color for it, if it has one. UI-agnostic and
/// synchronous — callers run it off the main thread.
struct TagService {
    func tags(of url: URL) throws -> [String] {
        try Platform.tags(of: url)
    }

    /// Replaces `url`'s tags with `tags` (an empty list removes them all).
    func setTags(_ tags: [String], on url: URL) throws {
        try Platform.setTags(tags, on: url)
    }

    /// `tags` with `newTag` added at the end — trimmed, and not added again
    /// if it's already there in any capitalization (Finder treats "red" and
    /// "Red" as the same tag).
    static func adding(_ newTag: String, to tags: [String]) -> [String] {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return tags }
        return tags + [trimmed]
    }

    static func removing(_ tag: String, from tags: [String]) -> [String] {
        tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }

    /// One tag across several items: on how many of them.
    struct Usage: Equatable {
        let tag: String
        let count: Int
    }

    /// The tags of several items, each once (any capitalization), in the
    /// order they first appear, with how many items have it.
    static func usage(in tagLists: [[String]]) -> [Usage] {
        var order: [String] = []
        var counts: [String: (tag: String, count: Int)] = [:]
        for tags in tagLists {
            var seenHere = Set<String>()
            for tag in tags {
                let key = tag.lowercased()
                guard seenHere.insert(key).inserted else { continue }
                if let existing = counts[key] {
                    counts[key] = (existing.tag, existing.count + 1)
                } else {
                    counts[key] = (tag, 1)
                    order.append(key)
                }
            }
        }
        return order.compactMap { counts[$0].map { Usage(tag: $0.tag, count: $0.count) } }
    }

    /// What the Inspector's Add Tag menu offers: the standard color tags,
    /// then the other tags used in this folder, minus those `current`
    /// already has.
    static func suggestions(standard: [String], inFolder: [[String]], excluding current: [String]) -> [String] {
        var seen = Set(current.map { $0.lowercased() })
        var result: [String] = []
        for tag in standard + inFolder.flatMap({ $0 }).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let key = tag.lowercased()
            guard !tag.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result
    }
}
