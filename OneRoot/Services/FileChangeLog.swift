import Foundation

/// Collects the `FileChange`s a multi-item copy/move makes as each item
/// completes, so a caller can still offer Undo for the items that finished
/// when the operation as a whole fails or is cancelled partway through.
/// Locked because `FileSystemService` appends from a background task while
/// the caller reads it afterwards on the main actor.
final class FileChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FileChange] = []

    var changes: [FileChange] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ change: FileChange) {
        lock.lock()
        storage.append(change)
        lock.unlock()
    }
}
