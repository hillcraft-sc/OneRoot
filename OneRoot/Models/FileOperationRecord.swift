import Foundation

/// How a copy, move, compress, or extract ended.
enum FileOperationOutcome: Equatable {
    case succeeded
    case cancelled
    /// `message` is the error as shown everywhere else; `detail` is what
    /// else is known — how far it got, the system's reason and code.
    case failed(message: String, detail: String?)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// The failure as recorded: `error`'s own description, plus how many
    /// of `total` items had finished and the underlying system error's
    /// reason and code when there is one.
    static func failure(_ error: Error, finished: Int, of total: Int) -> FileOperationOutcome {
        var lines: [String] = []
        if total > 1 {
            lines.append("\(finished) of \(total) items finished before it stopped.")
        }
        let underlying = Self.underlyingError(of: error)
        if let reason = underlying.localizedFailureReason, !reason.isEmpty { lines.append(reason) }
        if let suggestion = underlying.localizedRecoverySuggestion, !suggestion.isEmpty { lines.append(suggestion) }
        lines.append("Error: \(underlying.domain) \(underlying.code)")
        return .failed(message: error.localizedDescription, detail: lines.joined(separator: "\n"))
    }

    /// The system error under one of OneRoot's own, or `error` itself.
    private static func underlyingError(of error: Error) -> NSError {
        if let fileError = error as? FileSystemError, let underlying = fileError.underlyingError {
            return underlying as NSError
        }
        return error as NSError
    }
}

/// A finished operation, for the File Operations card's Recent list. Kept
/// for this run of the app only.
struct FileOperationRecord: Identifiable {
    let id: UUID
    let title: String
    let symbolName: String
    let outcome: FileOperationOutcome
    let finishedAt: Date
    /// From start to finish, preparing included.
    let duration: TimeInterval
    let sourceFolder: URL?
    let destinationFolder: URL?
    let itemCount: Int
    let finishedItems: Int
    let completedBytes: Int64
    /// `nil` when the operation couldn't report its size (compressing).
    let totalBytes: Int64?
    /// Runs the operation again for what didn't finish — `nil` where that
    /// isn't safe (compress and extract would start over).
    let retry: (@MainActor () -> Void)?
}
