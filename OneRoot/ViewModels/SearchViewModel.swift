import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var criteria: SearchCriteria
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var foldersScanned = 0
    private(set) var filesScanned = 0
    private(set) var filesSkipped = 0
    /// Cloud files left alone by a content search because they're only
    /// placeholders — see `SearchEvent.progress`.
    private(set) var notDownloaded = 0
    private(set) var errorMessage: String?
    /// How the current/last search ran — `nil` before the first one.
    private(set) var engine: SearchEngine?
    /// How many results came from the Spotlight index, once its phase is
    /// done — everything after that the full scan found on its own.
    private(set) var indexMatchCount: Int?
    /// Whether name/metadata searches may use the Spotlight index (see
    /// `SearchService.search`). Kept out of `SearchCriteria` so saved
    /// queries from before this existed still decode.
    var useSpotlightIndex: Bool {
        didSet { defaults.set(useSpotlightIndex, forKey: Self.useSpotlightIndexKey) }
    }

    private static let useSpotlightIndexKey = "com.oneroot.search.useSpotlightIndex"
    private let searchService: SearchService
    private let defaults: UserDefaults
    private var searchTask: Task<Void, Never>?

    init(
        searchService: SearchService = SearchService(),
        initialRoot: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaults: UserDefaults = .standard
    ) {
        self.searchService = searchService
        self.defaults = defaults
        self.criteria = SearchCriteria(root: initialRoot)
        self.useSpotlightIndex = defaults.object(forKey: Self.useSpotlightIndexKey) as? Bool ?? true
    }

    /// A content search needs text to look for; a name/metadata search
    /// doesn't (e.g. "every .pdf over 10 MB" is a legitimate search with no
    /// name pattern at all).
    var canSearch: Bool {
        criteria.mode == .nameAndMetadata || !criteria.pattern.isEmpty
    }

    func start() {
        searchTask?.cancel()
        results = []
        foldersScanned = 0
        filesScanned = 0
        filesSkipped = 0
        notDownloaded = 0
        errorMessage = nil
        engine = nil
        indexMatchCount = nil
        isSearching = true

        let criteria = self.criteria
        let useIndex = useSpotlightIndex
        searchTask = Task { [searchService] in
            do {
                for try await event in searchService.search(criteria, useIndex: useIndex) {
                    switch event {
                    case .engine(let engine):
                        self.engine = engine
                    case .indexPhaseFinished(let matches):
                        indexMatchCount = matches
                    case .matched(let result):
                        results.append(result)
                    case .progress(let folders, let files, let skipped, let notDownloaded):
                        foldersScanned = folders
                        filesScanned = files
                        filesSkipped = skipped
                        self.notDownloaded = notDownloaded
                    }
                }
            } catch is CancellationError {
                // User-initiated cancel — not a failure worth surfacing.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func cancel() {
        searchTask?.cancel()
    }

    /// Takes a folder's filter handed over by Search Subfolders, if one is
    /// waiting, and starts searching with it. Spotlight setting, scope
    /// toggles other than hidden files, and saved queries are untouched.
    func takeHandoff(from center: SearchHandoffCenter) {
        guard let handed = center.take() else { return }
        var criteria = handed
        criteria.includeCloudStorage = self.criteria.includeCloudStorage
        self.criteria = criteria
        start()
    }

    /// Clears one chip's condition. A running search is restarted, so the
    /// results always match the chips shown.
    func remove(_ field: SearchChip.Field) {
        criteria = SearchChipBuilder.removing(field, from: criteria)
        if isSearching, canSearch { start() }
    }
}
