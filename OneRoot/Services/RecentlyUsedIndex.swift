import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Recents on Linux: the freedesktop.org `recently-used.xbel` file that GTK
/// apps (and OneRoot, when it opens a file) record opened documents in.
/// It stands in for Spotlight's last-used dates — see `VirtualListingService`.
///
/// Pure parsing plus one file read; nothing here touches the real home
/// unless `xbelURL` is left at its default.
struct RecentlyUsedIndex: SearchIndexQuerying, RecentItemsQuerying {
    let xbelURL: URL
    private let now: @Sendable () -> Date

    init(
        xbelURL: URL = RecentlyUsedIndex.defaultURL(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.xbelURL = xbelURL
        self.now = now
    }

    /// `$XDG_DATA_HOME/recently-used.xbel`, else `~/.local/share/…`.
    static func defaultURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let data = environment["XDG_DATA_HOME"], data.hasPrefix("/") {
            return URL(fileURLWithPath: data, isDirectory: true).appendingPathComponent("recently-used.xbel")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/recently-used.xbel")
    }

    /// No index to search: callers walk the folders themselves.
    func paths(matching query: String, under root: URL) -> [String]? { nil }

    func recentlyUsed(withinDays days: Int, under roots: [URL]) -> [(path: String, lastUsed: Date)] {
        guard let data = try? Data(contentsOf: xbelURL) else { return [] }
        let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
        let prefixes = roots.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        return Self.entries(in: data).compactMap { entry in
            guard entry.lastUsed >= cutoff,
                  prefixes.contains(where: { entry.path.hasPrefix($0) }),
                  FileManager.default.fileExists(atPath: entry.path)
            else { return nil }
            return (entry.path, entry.lastUsed)
        }
    }

    struct Entry: Equatable {
        var path: String
        var lastUsed: Date
    }

    /// Every local file bookmark in an xbel document, dated by when it was
    /// last opened (`visited`, else `modified`, else `added`). Bookmarks
    /// that aren't `file://` URLs, or are malformed, are skipped; a document
    /// that isn't valid XML yields what was read before the error.
    static func entries(in data: Data) -> [Entry] {
        let parser = XMLParser(data: data)
        let reader = Reader()
        parser.delegate = reader
        parser.parse()
        return reader.entries
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var entries: [Entry] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "bookmark",
                  let href = attributeDict["href"],
                  let url = URL(string: href), url.isFileURL
            else { return }
            let date = ["visited", "modified", "added"]
                .compactMap { attributeDict[$0] }
                .compactMap(RecentlyUsedIndex.parseDate)
                .first
            guard let date else { return }
            entries.append(Entry(path: url.path, lastUsed: date))
        }
    }

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
