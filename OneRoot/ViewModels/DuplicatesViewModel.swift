import Foundation
import Observation

/// Hands folders to the Find Duplicates window, which may not be open yet
/// (same pattern as `SearchHandoffCenter`).
@MainActor
@Observable
final class DuplicatesHandoffCenter {
    static let shared = DuplicatesHandoffCenter()
    private(set) var pending: [URL]?

    func hand(_ roots: [URL]) { pending = roots }

    func take() -> [URL]? {
        defer { pending = nil }
        return pending
    }
}

/// The Find Duplicates window (#67): scans, lists groups of identical
/// files, and moves the ones you mark to the Trash — at least one of each
/// group always stays. Trashing records the origin for Put Back and is
/// undoable, as anywhere else in OneRoot.
@MainActor
@Observable
final class DuplicatesViewModel {
    enum State: Equatable {
        case idle
        case running(DuplicateFinder.Phase)
        case done
        case failed(String)
    }

    private(set) var roots: [URL] = []
    private(set) var state: State = .idle
    private(set) var groups: [DuplicateGroup] = []
    /// Files marked for the Trash.
    private(set) var marked: Set<URL> = []
    var errorMessage: String?

    private let finder: DuplicateFinder
    private let fileSystemService: FileSystemService
    private let trashOriginService: TrashOriginService
    private let undoCenter: FileUndoCenter
    @ObservationIgnored private var cancellation = CancellationFlag()
    @ObservationIgnored private var task: Task<Void, Never>?
    var includeHidden = false

    init(
        finder: DuplicateFinder = DuplicateFinder(),
        fileSystemService: FileSystemService = FileSystemService(),
        trashOriginService: TrashOriginService = TrashOriginService(),
        undoCenter: FileUndoCenter? = nil
    ) {
        self.finder = finder
        self.fileSystemService = fileSystemService
        self.trashOriginService = trashOriginService
        self.undoCenter = undoCenter ?? .shared
    }

    var reclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimable } }
    var markedSize: Int64 {
        groups.reduce(0) { total, group in total + group.size * Int64(group.files.filter { marked.contains($0.url) }.count) }
    }

    @discardableResult
    func start(_ roots: [URL]) -> Task<Void, Never> {
        cancel()
        self.roots = roots
        groups = []
        marked = []
        cancellation = CancellationFlag()
        let flag = cancellation
        state = .running(.scanning(files: 0))
        let finder = finder
        let includeHidden = includeHidden
        let report: @MainActor (DuplicateFinder.Phase) -> Void = { [weak self] phase in
            guard !flag.isCancelled, case .running = self?.state else { return }
            self?.state = .running(phase)
        }
        let task = Task { [weak self] in
            do {
                let found = try await finder.find(in: roots, includeHidden: includeHidden, cancellation: flag) { phase in
                    Task { @MainActor in report(phase) }
                }
                guard let self, !flag.isCancelled else { return }
                self.groups = found
                self.state = .done
            } catch is CancellationError {
                guard let self, self.cancellation === flag else { return }
                self.state = .idle
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        cancellation.cancel()
        task?.cancel()
        task = nil
        if case .running = state { state = .idle }
    }

    func isMarked(_ file: DuplicateFile) -> Bool { marked.contains(file.url) }

    /// Whether `file` can be marked: not if it's the last unmarked one in
    /// its group.
    func canMark(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        marked.contains(file.url) || group.files.filter { !marked.contains($0.url) }.count > 1
    }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if marked.contains(file.url) {
            marked.remove(file.url)
        } else if canMark(file, in: group) {
            marked.insert(file.url)
        }
    }

    /// Marks everything but the oldest (or newest) copy in every group.
    func markAllButOne(keepingNewest: Bool) {
        var result: Set<URL> = []
        for group in groups {
            let keep = keepingNewest ? group.files.last : group.files.first
            for file in group.files where file.url != keep?.url { result.insert(file.url) }
        }
        marked = result
    }

    func clearMarks() { marked = [] }

    /// Moves the marked files to the Trash (after `confirm`), then takes
    /// them out of the list.
    @discardableResult
    func trashMarked(confirm: (([String]) -> Bool)? = nil) -> Task<Void, Never>? {
        let urls = groups.flatMap(\.files).map(\.url).filter { marked.contains($0) }
        let names = urls.map(\.lastPathComponent)
        guard !urls.isEmpty, confirm?(names) ?? Platform.confirmTrash(names) else { return nil }
        return Task {
            let fallback = await TrashFallback.deleteItemsWithoutTrash(
                await fileSystemService.moveToTrash(urls),
                confirm: { Platform.confirmDeleteWithoutTrash($0) },
                fileSystemService: fileSystemService
            )
            let result = fallback.result
            var changes: [FileChange] = []
            for url in result.trashed {
                guard let trashedURL = result.locations[url] else { continue }
                trashOriginService.recordOrigin(trashedURL: trashedURL, originalURL: url)
                changes.append(.trashed(original: url, trashedAt: trashedURL))
            }
            if !changes.isEmpty { undoCenter.record(changes, actionName: "Move to Trash") }
            Platform.progress.recordTrash(urls.filter { !fallback.deleted.contains($0) }, result: result, retry: nil)
            if let message = fallback.errorMessage { errorMessage = message }
            let gone = Set(result.trashed).union(fallback.deleted)
            marked.subtract(gone)
            groups = groups.compactMap { group in
                var group = group
                group.files.removeAll { gone.contains($0.url) }
                return group.files.count > 1 ? group : nil
            }
        }
    }
}
