import Foundation

/// Where copies, moves, and other long file operations report their
/// progress. On macOS that's `FileOperationProgressCenter` (the progress
/// windows and the File Operations card); the Linux app supplies its own.
/// Services talk only to this, so they build on both (#79).
@MainActor
protocol FileOperationProgressReporting: AnyObject {
    func beginOperation(
        title: String,
        symbolName: String,
        totalBytes: Int64,
        isIndeterminate: Bool,
        isPreparing: Bool,
        sourceFolder: URL?,
        destinationFolder: URL?,
        itemCount: Int,
        opensFloatingWindow: Bool,
        pauseControl: PauseControl?,
        startNow: (() -> Void)?,
        cancel: @escaping () -> Void
    ) -> UUID
    func startTransfer(_ id: UUID, totalBytes: Int64)
    func setCurrentItem(_ id: UUID, index: Int, name: String)
    func update(_ id: UUID, completedBytes: Int64)
    func setWaiting(_ id: UUID, _ isWaiting: Bool)
    func setVerifying(_ id: UUID, _ isVerifying: Bool)
    func finishOperation(_ id: UUID, outcome: FileOperationOutcome, finishedItems: Int?, retry: (@MainActor () -> Void)?)
    func recordOperation(
        title: String,
        symbolName: String,
        outcome: FileOperationOutcome,
        itemCount: Int,
        finishedItems: Int,
        sourceFolder: URL?,
        destinationFolder: URL?,
        retry: (@MainActor () -> Void)?
    )
    func recordTrash(_ urls: [URL], result: TrashResult, retry: (@MainActor ([URL]) -> Void)?)
}

/// The defaults the call sites rely on.
extension FileOperationProgressReporting {
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
        beginOperation(
            title: title, symbolName: symbolName, totalBytes: totalBytes, isIndeterminate: isIndeterminate,
            isPreparing: isPreparing, sourceFolder: sourceFolder, destinationFolder: destinationFolder,
            itemCount: itemCount, opensFloatingWindow: opensFloatingWindow, pauseControl: pauseControl,
            startNow: startNow, cancel: cancel
        )
    }

    func finish(_ id: UUID, outcome: FileOperationOutcome = .succeeded, finishedItems: Int? = nil, retry: (@MainActor () -> Void)? = nil) {
        finishOperation(id, outcome: outcome, finishedItems: finishedItems, retry: retry)
    }

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
        recordOperation(
            title: title, symbolName: symbolName, outcome: outcome, itemCount: itemCount, finishedItems: finishedItems,
            sourceFolder: sourceFolder, destinationFolder: destinationFolder, retry: retry
        )
    }
}

/// Labels shared by every progress reporter.
enum FileOperationLabels {
    /// "Moving “a.txt” to the Trash", "Moving 3 items to the Trash".
    static func title(_ verb: String, _ urls: [URL], suffix: String = "") -> String {
        let items = urls.count == 1 ? "\u{201C}\(urls[0].lastPathComponent)\u{201D}" : "\(urls.count) items"
        return "\(verb) \(items)\(suffix)"
    }

    /// The folder all of `urls` are in, if they share one.
    static func commonFolder(_ urls: [URL]) -> URL? {
        let parents = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        return parents.count == 1 ? parents.first : nil
    }
}

/// Forwards byte counts from a copying thread to `FileOperationProgressCenter`
/// at most ~10 times a second — `copyfile` reports far more often than a
/// progress bar needs. Main-queue dispatch keeps updates in order.
final class ProgressReporter: @unchecked Sendable {
    private let id: UUID
    private let reporter: @MainActor () -> FileOperationProgressReporting
    private let lock = NSLock()
    private var lastSent = Date.distantPast

    init(id: UUID, reporter: @escaping @MainActor () -> FileOperationProgressReporting) {
        self.id = id
        self.reporter = reporter
    }

    /// `force` for the final count of an item, so it's never throttled away.
    func report(_ completedBytes: Int64, force: Bool = false) {
        let now = Date()
        lock.lock()
        guard force || now.timeIntervalSince(lastSent) >= 0.1 else {
            lock.unlock()
            return
        }
        lastSent = now
        lock.unlock()
        let id = id
        let reporter = reporter
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                reporter().update(id, completedBytes: completedBytes)
            }
        }
    }
}
