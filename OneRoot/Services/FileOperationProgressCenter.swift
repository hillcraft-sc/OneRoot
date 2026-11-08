import Foundation
import Observation

/// One Copy/Move/Compress/Extract in flight — enough to render a
/// Finder-style progress popup (see `FileOperationProgressView`) and to
/// cancel the underlying work.
struct FileOperationProgress: Identifiable {
    let id = UUID()
    var title: String
    /// SF Symbol name shown next to the title — "folder.fill" for copy/
    /// move, "archivebox.fill" for compress/extract.
    var symbolName: String
    var completedBytes: Int64
    var totalBytes: Int64
    /// True for compress (ditto reports no progress) and for extracting a
    /// non-zip format — see `ArchiveSizeInspector`.
    var isIndeterminate: Bool
    /// Copy/move only: still adding up how much there is to do, before any
    /// bytes move — the popup says "Preparing…".
    var isPreparing: Bool
    /// When bytes started moving (reset by `startTransfer`), so speed and
    /// time remaining don't count the preparing phase.
    var startDate: Date
    /// When the operation began, preparing included — for how long it took.
    var beganAt: Date
    /// The folder the items come from, when they share one.
    var sourceFolder: URL?
    /// The folder they go to (for compress and extract, where the result
    /// is written).
    var destinationFolder: URL?
    var itemCount: Int
    /// 0-based; the item being worked on now.
    var currentItemIndex: Int
    var currentItemName: String?
    var cancel: () -> Void
    /// Set for work that can truly stop and carry on (copies, moves to
    /// another volume, compress and extract); `nil` means no Pause button.
    var pauseControl: PauseControl?
    var isPaused = false
    /// Time spent paused since `startDate`, finished pauses only.
    var pausedDuration: TimeInterval = 0
    /// When the current pause began.
    var pausedSince: Date?
    /// Cancel was pressed and the operation is winding down (an item
    /// mid-copy finishes or is rolled back first) — shown as "Cancelling…"
    /// so the click is visibly taken.
    var isCancelling = false
    /// Whether it may get its own floating progress window. Not for work
    /// that's over in a blink (tagging), where one would just flash.
    var opensFloatingWindow = true
    /// Waiting its turn behind another copy to the same disk
    /// (`FileTransferQueue`); `startNow` lets it go ahead anyway.
    var isWaiting = false
    var startNow: (() -> Void)?
    /// Reading the finished copy back to check it (Verify copies).
    var isVerifying = false
    /// Recent (time, bytes done) readings, for the current speed rather
    /// than the average since the start — a copy that starts with big
    /// files and ends in thousands of small ones (or the reverse) would
    /// otherwise show a speed and time left that drift for minutes.
    var rateSamples: [RateSample] = []

    struct RateSample: Equatable {
        let date: Date
        let bytes: Int64
    }

    /// How far back the current speed looks.
    static let rateWindow: TimeInterval = 10

    /// Bytes per second over the last `rateWindow`, once readings span at
    /// least 3 seconds; `nil` before that.
    var recentRate: Double? {
        guard let first = rateSamples.first, let last = rateSamples.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= 3 else { return nil }
        return Double(last.bytes - first.bytes) / span
    }

    /// Adds a reading, keeping one just outside the window as the anchor.
    mutating func recordRateSample(bytes: Int64, at date: Date) {
        if let last = rateSamples.last, date.timeIntervalSince(last.date) < 0.5 { return }
        rateSamples.append(RateSample(date: date, bytes: bytes))
        while rateSamples.count > 2, date.timeIntervalSince(rateSamples[1].date) >= Self.rateWindow {
            rateSamples.removeFirst()
        }
    }

    var canPause: Bool { pauseControl != nil && !isCancelling && !isPreparing && !isWaiting }

    /// Time since `startDate` spent actually working — paused time left
    /// out, so speed and time remaining stay honest.
    func activeElapsed(at now: Date) -> TimeInterval {
        let pausedNow = pausedSince.map { now.timeIntervalSince($0) } ?? 0
        return now.timeIntervalSince(startDate) - pausedDuration - pausedNow
    }
}

/// App-wide registry of in-flight file operations — shared rather than
/// scoped to whichever tab/window started one, same reasoning as
/// `ArchiveProcessRegistry`: a copy started from one tab should show its
/// progress (and be cancelable, and block a careless Quit) regardless of
/// which window ends up frontmost. `RootView` observes `operations` to open
/// a floating window per entry; `AppDelegate` consults it on Quit.
@MainActor
@Observable
final class FileOperationProgressCenter {
    static let shared = FileOperationProgressCenter()

    private(set) var operations: [FileOperationProgress] = [] {
        didSet {
            let ids = Set(operations.map(\.id))
            if ids != operationIDs { operationIDs = ids }
        }
    }
    /// The running operations' ids — changes only when one starts or
    /// ends, so watching it doesn't redraw on every progress tick.
    private(set) var operationIDs: Set<UUID> = []
    /// Finished operations, newest first — at most `maxRecent`.
    private(set) var recent: [FileOperationRecord] = []
    /// Failures since the File Operations card was last on screen, for the
    /// status line's "1 failed".
    private(set) var unseenFailureCount = 0
    /// Main windows whose tool row (with the File Operations card) is
    /// showing, by window number, and the main window most recently key —
    /// while that one shows the card, operations get no floating window.
    private(set) var windowsShowingCard: Set<Int> = []
    private(set) var frontWindowNumber: Int?

    static let maxRecent = 30
    /// Settings ▸ General ▸ "Show progress in the window": operations open
    /// the front window's File Operations card instead of popups.
    static let showsProgressInWindowKey = "com.oneroot.fileOperations.showProgressInWindow"

    private let defaults: UserDefaults
    /// Says a finished operation out loud (VoiceOver), once for the app —
    /// set by `AppDelegate`, which can reach AppKit's announcements.
    var announce: ((String) -> Void)?

    /// For tests; the app uses `shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showsProgressInWindow: Bool {
        defaults.bool(forKey: Self.showsProgressInWindowKey)
    }

    /// Whether operations should open their own floating progress window:
    /// not while the frontmost main window shows the File Operations card,
    /// and never with "Show progress in the window" on (that window opens
    /// the card itself) — unless no main window is open to show it.
    var showsFloatingWindows: Bool {
        guard let frontWindowNumber else { return true }
        if showsProgressInWindow { return false }
        return !windowsShowingCard.contains(frontWindowNumber)
    }

    /// Cancel, from the card or a progress window: marks the operation
    /// as cancelling at once, then asks it to stop. Pressing again does
    /// nothing more.
    func requestCancel(_ id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }), !operations[index].isCancelling else { return }
        operations[index].isCancelling = true
        // Cancelling wakes a paused copy and continues a stopped process
        // so it can stop for good and roll back.
        endPause(at: index)
        operations[index].cancel()
    }

    /// Pause, from the card or a progress window. Only for operations that
    /// can really stop and carry on (`pauseControl`).
    func requestPause(_ id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }),
              operations[index].canPause, !operations[index].isPaused,
              let control = operations[index].pauseControl else { return }
        operations[index].isPaused = true
        operations[index].pausedSince = Date()
        operations[index].rateSamples = [] // the pause isn't part of the speed
        control.pause()
    }

    func requestResume(_ id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }), operations[index].isPaused else { return }
        endPause(at: index)
        operations[index].pauseControl?.resume()
    }

    private func endPause(at index: Int) {
        guard operations[index].isPaused else { return }
        if let since = operations[index].pausedSince {
            operations[index].pausedDuration += Date().timeIntervalSince(since)
        }
        operations[index].isPaused = false
        operations[index].pausedSince = nil
    }

    func setCardShowing(_ isShowing: Bool, inWindow number: Int) {
        if isShowing {
            windowsShowingCard.insert(number)
            unseenFailureCount = 0
        } else {
            windowsShowingCard.remove(number)
        }
    }

    /// A main window closed: it no longer shows the card, nor is it the
    /// front window operations could open their card in.
    func windowClosed(_ number: Int) {
        windowsShowingCard.remove(number)
        if frontWindowNumber == number { frontWindowNumber = nil }
    }

    func windowBecameFront(_ number: Int) {
        if frontWindowNumber != number { frontWindowNumber = number }
        if windowsShowingCard.contains(number) { unseenFailureCount = 0 }
    }

    func removeRecord(_ id: UUID) {
        recent.removeAll { $0.id == id }
    }

    /// Clears the finished operations that failed (`failures`) or the rest.
    func clearRecent(failures: Bool) {
        recent.removeAll { $0.outcome.isFailure == failures }
    }

    /// Retries a failed operation: drops its record, then runs it again.
    func retry(_ id: UUID) {
        guard let record = recent.first(where: { $0.id == id }), let retry = record.retry else { return }
        removeRecord(id)
        retry()
    }

    @discardableResult
    func begin(
        title: String,
        symbolName: String,
        totalBytes: Int64,
        isIndeterminate: Bool = false,
        isPreparing: Bool = false,
        sourceFolder: URL? = nil,
        destinationFolder: URL? = nil,
        itemCount: Int = 1,
        opensFloatingWindow: Bool = true,
        pauseControl: PauseControl? = nil,
        startNow: (() -> Void)? = nil,
        cancel: @escaping () -> Void
    ) -> UUID {
        let now = Date()
        let operation = FileOperationProgress(
            title: title,
            symbolName: symbolName,
            completedBytes: 0,
            totalBytes: totalBytes,
            isIndeterminate: isIndeterminate || isPreparing,
            isPreparing: isPreparing,
            startDate: now,
            beganAt: now,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            itemCount: itemCount,
            currentItemIndex: 0,
            currentItemName: nil,
            cancel: cancel,
            pauseControl: pauseControl,
            opensFloatingWindow: opensFloatingWindow
        )
        var added = operation
        added.startNow = startNow
        operations.append(added)
        return added.id
    }

    func setWaiting(_ id: UUID, _ isWaiting: Bool) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].isWaiting = isWaiting
    }

    /// Start Now, for an operation waiting its turn.
    func requestStartNow(_ id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }), operations[index].isWaiting else { return }
        operations[index].startNow?()
    }

    func setVerifying(_ id: UUID, _ isVerifying: Bool) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].isVerifying = isVerifying
    }

    /// Ends an `isPreparing` phase: the total is known and bytes start moving.
    func startTransfer(_ id: UUID, totalBytes: Int64) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].totalBytes = totalBytes
        operations[index].isPreparing = false
        operations[index].isIndeterminate = false
        operations[index].startDate = Date()
        operations[index].pausedDuration = 0
        operations[index].rateSamples = []
        if operations[index].isPaused { operations[index].pausedSince = operations[index].startDate }
    }

    func setCurrentItem(_ id: UUID, index: Int, name: String) {
        guard let position = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[position].currentItemIndex = index
        operations[position].currentItemName = name
    }

    func update(_ id: UUID, completedBytes: Int64) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].completedBytes = completedBytes
        if !operations[index].isPaused {
            operations[index].recordRateSample(bytes: completedBytes, at: Date())
        }
    }

    /// Ends an operation and adds it to `recent`. `finishedItems` is how
    /// many items were done (all of them when it succeeded, unless said
    /// otherwise); `retry` is only kept for a failure.
    func finish(
        _ id: UUID,
        outcome: FileOperationOutcome = .succeeded,
        finishedItems: Int? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        let operation = operations.remove(at: index)
        let isFailure: Bool
        if case .failed = outcome { isFailure = true } else { isFailure = false }
        let finishedAt = Date()
        insert(FileOperationRecord(
            id: operation.id,
            title: operation.title,
            symbolName: operation.symbolName,
            outcome: outcome,
            finishedAt: finishedAt,
            duration: finishedAt.timeIntervalSince(operation.beganAt),
            sourceFolder: operation.sourceFolder,
            destinationFolder: operation.destinationFolder,
            itemCount: operation.itemCount,
            finishedItems: finishedItems ?? (outcome == .succeeded ? operation.itemCount : operation.currentItemIndex),
            completedBytes: operation.completedBytes,
            totalBytes: operation.isIndeterminate ? nil : operation.totalBytes,
            retry: isFailure ? retry : nil
        ))
    }

    /// Adds an operation that had no progress to show — Move to Trash,
    /// Delete Immediately, Put Back — to `recent`.
    func record(
        title: String,
        symbolName: String,
        outcome: FileOperationOutcome,
        itemCount: Int,
        finishedItems: Int,
        sourceFolder: URL? = nil,
        destinationFolder: URL? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        insert(FileOperationRecord(
            id: UUID(),
            title: title,
            symbolName: symbolName,
            outcome: outcome,
            finishedAt: Date(),
            duration: 0,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            itemCount: itemCount,
            finishedItems: finishedItems,
            completedBytes: 0,
            totalBytes: nil,
            retry: outcome.isFailure ? retry : nil
        ))
    }

    /// Records a Move to Trash; Retry trashes the items that didn't go.
    func recordTrash(_ urls: [URL], result: TrashResult, retry: (@MainActor ([URL]) -> Void)?) {
        guard !urls.isEmpty else { return }
        let remaining = result.failures.map(\.url)
        record(
            title: Self.title("Moving", urls, suffix: " to the Trash"),
            symbolName: "trash",
            outcome: result.failures.first.map { .failure($0.error, finished: result.trashed.count, of: urls.count) } ?? .succeeded,
            itemCount: urls.count,
            finishedItems: result.trashed.count,
            sourceFolder: Self.commonFolder(urls),
            retry: retry.map { retry in { retry(remaining) } }
        )
    }

    /// See `FileOperationLabels`.
    static func title(_ verb: String, _ urls: [URL], suffix: String = "") -> String {
        FileOperationLabels.title(verb, urls, suffix: suffix)
    }

    static func commonFolder(_ urls: [URL]) -> URL? {
        FileOperationLabels.commonFolder(urls)
    }

    /// "Copying 3 items to “Talk” finished", "… was cancelled", "… failed: reason".
    static func announcement(for record: FileOperationRecord) -> String {
        switch record.outcome {
        case .succeeded: return "\(record.title) finished"
        case .cancelled: return "\(record.title) was cancelled"
        case .failed(let message, _): return "\(record.title) failed: \(message)"
        }
    }

    private func insert(_ record: FileOperationRecord) {
        announce?(Self.announcement(for: record))
        recent.insert(record, at: 0)
        if recent.count > Self.maxRecent { recent.removeLast(recent.count - Self.maxRecent) }
        if record.outcome.isFailure, showsFloatingWindows { unseenFailureCount += 1 }
    }
}

/// The progress windows and File Operations card are where macOS shows it.
extension FileOperationProgressCenter: FileOperationProgressReporting {
    func beginOperation(
        title: String, symbolName: String, totalBytes: Int64, isIndeterminate: Bool, isPreparing: Bool,
        sourceFolder: URL?, destinationFolder: URL?, itemCount: Int, opensFloatingWindow: Bool,
        pauseControl: PauseControl?, startNow: (() -> Void)?, cancel: @escaping () -> Void
    ) -> UUID {
        begin(
            title: title, symbolName: symbolName, totalBytes: totalBytes, isIndeterminate: isIndeterminate,
            isPreparing: isPreparing, sourceFolder: sourceFolder, destinationFolder: destinationFolder,
            itemCount: itemCount, opensFloatingWindow: opensFloatingWindow, pauseControl: pauseControl,
            startNow: startNow, cancel: cancel
        )
    }

    func finishOperation(_ id: UUID, outcome: FileOperationOutcome, finishedItems: Int?, retry: (@MainActor () -> Void)?) {
        finish(id, outcome: outcome, finishedItems: finishedItems, retry: retry)
    }

    func recordOperation(
        title: String, symbolName: String, outcome: FileOperationOutcome, itemCount: Int, finishedItems: Int,
        sourceFolder: URL?, destinationFolder: URL?, retry: (@MainActor () -> Void)?
    ) {
        record(
            title: title, symbolName: symbolName, outcome: outcome, itemCount: itemCount, finishedItems: finishedItems,
            sourceFolder: sourceFolder, destinationFolder: destinationFolder, retry: retry
        )
    }
}
