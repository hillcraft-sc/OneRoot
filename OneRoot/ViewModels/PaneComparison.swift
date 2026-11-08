import Foundation
import Observation

/// Compare Panes (View ▸ Compare Panes, or Compare in the Context Bar with
/// Dual Pane on): compares a split tab's two folders, shows each item's
/// status in both lists, and copies what's newer or missing from one side
/// to the other. Ends by itself when either pane goes to another folder or
/// the panes are swapped or closed — the results would no longer match
/// what's shown.
@MainActor
@Observable
final class PaneComparison {
    enum State: Equatable {
        case comparing(scanned: Int)
        case done(FolderComparison)
        case failed(String)
    }

    /// A pending Copy to Left/Right, shown as a preview before anything is
    /// copied.
    struct SyncPlan: Identifiable {
        let id = UUID()
        let toRight: Bool
        let items: [URL]
        let statuses: [String: ComparisonStatus]
        let destination: URL
        /// Files that differ but aren't newer here — left alone.
        let notCopied: [String]
    }

    private(set) var state: State = .comparing(scanned: 0)
    var showsOnlyDifferences = false {
        didSet { applyToPanes() }
    }
    var pendingSync: SyncPlan?

    let left: FileListViewModel
    let right: FileListViewModel
    let leftURL: URL
    let rightURL: URL
    /// Called when the comparison should go away (Done, or the panes
    /// changed); the tab drops it.
    var onEnd: () -> Void = {}

    private let service: FolderComparisonService
    private var cancellation = CancellationFlag()
    private var task: Task<Void, Never>?
    @ObservationIgnored private var watchers: [ObservationWatch] = []

    init?(left: FileListViewModel, right: FileListViewModel, service: FolderComparisonService = FolderComparisonService()) {
        guard let leftURL = left.currentDirectory, let rightURL = right.currentDirectory else { return nil }
        self.left = left
        self.right = right
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.service = service
        // Either pane moving on ends the comparison.
        watchers = [left, right].map { pane in
            let start = pane.currentDirectory
            return ObservationWatch.watch({ pane.currentDirectory }, emitsInitialValue: false) { [weak self] url in
                if url != start { self?.end() }
            }
        }
    }

    var comparison: FolderComparison? {
        if case .done(let comparison) = state { return comparison }
        return nil
    }

    var isComparing: Bool {
        if case .comparing = state { return true }
        return false
    }

    func start() {
        task?.cancel()
        cancellation.cancel()
        cancellation = CancellationFlag()
        let flag = cancellation
        state = .comparing(scanned: 0)
        applyToPanes()
        let report: @MainActor (Int) -> Void = { [weak self] scanned in
            if case .comparing = self?.state { self?.state = .comparing(scanned: scanned) }
        }
        task = Task { [weak self, service, leftURL, rightURL] in
            do {
                let result = try await service.compare(leftURL, rightURL, cancellation: flag) { scanned in
                    // Coalesced: only every few hundred items reach the UI.
                    guard scanned % 250 == 0 else { return }
                    Task { @MainActor in report(scanned) }
                }
                guard let self, !flag.isCancelled else { return }
                self.state = .done(result)
                self.applyToPanes()
            } catch is CancellationError {
                // Cancelled or ended; nothing to show.
            } catch {
                guard let self, !flag.isCancelled else { return }
                self.state = .failed("Couldn\u{2019}t compare the folders: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel while comparing, or Done afterwards: clears both panes'
    /// statuses and filters.
    func end() {
        cancellation.cancel()
        task?.cancel()
        task = nil
        watchers.removeAll()
        for pane in [left, right] {
            pane.comparisonStatuses = nil
            pane.comparisonFilter = nil
        }
        onEnd()
    }

    /// Prepares Copy to Right (or Left) and shows its preview.
    func planSync(toRight: Bool) {
        guard let comparison else { return }
        let statuses = comparison.statuses(onLeft: toRight)
        let folder = toRight ? leftURL : rightURL
        let isDirectory: (URL) -> Bool = { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        let items = FolderComparisonService.itemsToCopy(from: statuses, in: folder, isDirectory: isDirectory)
        let notCopied = statuses
            .filter { $0.value == .differs && !isDirectory(folder.appendingPathComponent($0.key)) }
            .map(\.key)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        pendingSync = SyncPlan(toRight: toRight, items: items, statuses: statuses, destination: toRight ? rightURL : leftURL, notCopied: notCopied)
    }

    /// Runs the previewed copy, then compares again.
    func performSync(_ plan: SyncPlan) {
        pendingSync = nil
        guard !plan.items.isEmpty else { return }
        let source = plan.toRight ? left : right
        let destinationPane = plan.toRight ? right : left
        let transfer = source.transfer(plan.items, into: plan.destination, move: false, resolveConflicts: { request in
            FolderComparisonService.syncAnswer(for: request)
        })
        Task { [weak self] in
            await transfer.value
            destinationPane.refresh()
            self?.start()
        }
    }

    /// Pushes the statuses (and the Differences Only filter) into each
    /// pane's list.
    private func applyToPanes() {
        guard let comparison else {
            left.comparisonStatuses = nil
            right.comparisonStatuses = nil
            left.comparisonFilter = nil
            right.comparisonFilter = nil
            return
        }
        for (pane, onLeft) in [(left, true), (right, false)] {
            let statuses = comparison.statuses(onLeft: onLeft)
            pane.comparisonStatuses = statuses
            pane.comparisonFilter = showsOnlyDifferences ? Set(statuses.filter { $0.value != .same }.keys) : nil
        }
    }
}
