import Foundation

/// Whether Advanced Search matches file/folder names and metadata, or
/// searches inside file contents (grep-style). See `SearchService`.
enum SearchMode: String, CaseIterable, Codable, Equatable {
    case nameAndMetadata
    case contents

    var title: String {
        switch self {
        case .nameAndMetadata: return "Name & Metadata"
        case .contents: return "File Contents"
        }
    }
}

/// How `SearchCriteria.pattern` is interpreted. Content-mode searches only
/// offer `.contains`/`.regex` in the UI (start/end-of-line matching isn't a
/// meaningful concept for "does this line contain the text"), but
/// `SearchService` handles all four uniformly for both names and lines.
enum SearchPatternMode: String, CaseIterable, Codable, Equatable {
    case contains
    case startsWith
    case endsWith
    case regex

    var title: String {
        switch self {
        case .contains: return "Contains"
        case .startsWith: return "Starts With"
        case .endsWith: return "Ends With"
        case .regex: return "Regex"
        }
    }
}

/// Narrows `.nameAndMetadata` search results to folders, files, or both.
/// Only meaningful in that mode — `.contents` search only ever looks at
/// file contents, so folders are already excluded regardless.
enum SearchItemType: String, CaseIterable, Codable, Equatable {
    case foldersOnly
    case filesOnly
    case filesAndFolders

    var title: String {
        switch self {
        case .foldersOnly: return "Folders"
        case .filesOnly: return "Files"
        case .filesAndFolders: return "Files & Folders"
        }
    }
}

/// A modified-date filter relative to now ("This Month"), so a saved
/// query or a filter left on keeps meaning the same thing tomorrow —
/// unlike `modifiedAfter`, a fixed date.
enum SearchDateRange: String, CaseIterable, Codable, Equatable, Identifiable {
    case today, thisWeek, thisMonth, thisYear

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        }
    }

    /// When the range starts, in `calendar`'s idea of weeks and months.
    func start(now: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .thisWeek: component = .weekOfYear
        case .thisMonth: component = .month
        case .thisYear: component = .year
        }
        return calendar.dateInterval(of: component, for: now)?.start ?? calendar.startOfDay(for: now)
    }
}

/// Everything `SearchService.search(_:)` needs to run one search — and,
/// minus `root`, `mode`, and the scope toggles, the current folder's filter
/// too (`FileListViewModel.filter`): one model, matched by
/// `SearchCriteriaMatcher` in both places, shown as chips by
/// `SearchChipBuilder`. Kept UI-agnostic (Foundation-only).
struct SearchCriteria: Codable, Equatable {
    var root: URL
    var mode: SearchMode = .nameAndMetadata
    var pattern: String = ""
    var patternMode: SearchPatternMode = .contains
    var caseSensitive: Bool = false
    var itemType: SearchItemType = .filesAndFolders
    /// Lowercase, no leading dot. Empty means "any extension".
    var extensions: [String] = []
    var minSizeBytes: Int64?
    var maxSizeBytes: Int64?
    var modifiedAfter: Date?
    var modifiedBefore: Date?
    var includeHidden: Bool = false
    /// Also search iCloud Drive and the other cloud providers (Nextcloud,
    /// Google Drive, Dropbox, …) when `root` contains them. They live under
    /// `~/Library`, which a search skips as hidden, so a search of the home
    /// folder or the whole volume never looked there. Off by default. See
    /// `SearchService`.
    var includeCloudStorage: Bool = false
    /// Any of these kinds (images, documents, …). Empty means any kind.
    var kinds: [StorageCategory] = []
    var modifiedWithin: SearchDateRange?
    /// Every one of these Finder tags (case-insensitive).
    var tags: [String] = []
    /// More folders to search besides `root` — a Workspace's other folders.
    var additionalRoots: [URL] = []
    /// The Workspace these folders are, for saying "Search in: Workspace X".
    var workspaceName: String?

    /// Every folder to search: `root` and the others, each once, leaving
    /// out any that's inside another (it's searched with that one).
    var searchRoots: [URL] {
        var roots: [URL] = []
        for url in [root] + additionalRoots {
            let path = url.standardizedFileURL.path
            guard !roots.contains(where: { $0.standardizedFileURL.path == path }) else { continue }
            roots.append(url)
        }
        return roots.filter { url in
            let path = url.standardizedFileURL.path
            return !roots.contains { other in
                let parent = other.standardizedFileURL.path
                return parent != path && path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
            }
        }
    }

    /// Whether anything narrows the items down — the root, mode, and scope
    /// toggles (hidden, cloud) aside. A folder shows its filter chips only
    /// then.
    var hasFilters: Bool {
        !pattern.isEmpty || itemType != .filesAndFolders || !extensions.isEmpty
            || minSizeBytes != nil || maxSizeBytes != nil || modifiedAfter != nil || modifiedBefore != nil
            || modifiedWithin != nil || !kinds.isEmpty || !tags.isEmpty
    }

    /// Whether anything besides the name pattern narrows the items.
    var hasFiltersBesidesName: Bool {
        var withoutName = self
        withoutName.pattern = ""
        return withoutName.hasFilters
    }

    /// The same filters with nothing narrowing them — a folder's "Clear".
    func clearingFilters() -> SearchCriteria {
        var cleared = SearchCriteria(root: root)
        cleared.mode = mode
        cleared.includeHidden = includeHidden
        cleared.includeCloudStorage = includeCloudStorage
        return cleared
    }
}

/// Written out by hand so a saved query from before `includeCloudStorage`
/// existed still loads: a synthesized decoder fails on a missing key, even
/// one with a default, which would have lost every saved query. (In this
/// file so it can use the synthesized `CodingKeys`.)
extension SearchCriteria {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(root: try values.decode(URL.self, forKey: .root))
        mode = try values.decodeIfPresent(SearchMode.self, forKey: .mode) ?? mode
        pattern = try values.decodeIfPresent(String.self, forKey: .pattern) ?? pattern
        patternMode = try values.decodeIfPresent(SearchPatternMode.self, forKey: .patternMode) ?? patternMode
        caseSensitive = try values.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? caseSensitive
        itemType = try values.decodeIfPresent(SearchItemType.self, forKey: .itemType) ?? itemType
        extensions = try values.decodeIfPresent([String].self, forKey: .extensions) ?? extensions
        minSizeBytes = try values.decodeIfPresent(Int64.self, forKey: .minSizeBytes)
        maxSizeBytes = try values.decodeIfPresent(Int64.self, forKey: .maxSizeBytes)
        modifiedAfter = try values.decodeIfPresent(Date.self, forKey: .modifiedAfter)
        modifiedBefore = try values.decodeIfPresent(Date.self, forKey: .modifiedBefore)
        includeHidden = try values.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? includeHidden
        includeCloudStorage = try values.decodeIfPresent(Bool.self, forKey: .includeCloudStorage) ?? includeCloudStorage
        kinds = try values.decodeIfPresent([StorageCategory].self, forKey: .kinds) ?? kinds
        modifiedWithin = try values.decodeIfPresent(SearchDateRange.self, forKey: .modifiedWithin)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? tags
        additionalRoots = try values.decodeIfPresent([URL].self, forKey: .additionalRoots) ?? additionalRoots
        workspaceName = try values.decodeIfPresent(String.self, forKey: .workspaceName)
    }
}
