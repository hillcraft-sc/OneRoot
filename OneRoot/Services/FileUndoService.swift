import Foundation

/// The outcome of reverting a batch of `FileChange`s: the changes reverting
/// made (what Redo should revert in turn), plus the error that stopped it
/// early, if any. Partial on failure rather than all-or-nothing — whatever
/// did get reverted stays redoable.
struct FileUndoResult {
    var reverted: [FileChange]
    var error: Error?
}

enum FileUndoError: LocalizedError {
    case missing(String)
    case occupied(String)
    case failed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "Can't undo: \"\(name)\" is no longer where OneRoot left it."
        case .occupied(let name):
            return "Can't undo: something named \"\(name)\" is already in its original location."
        case .failed(let name, let underlying):
            return "Can't undo the change to \"\(name)\": \(underlying.localizedDescription)"
        }
    }
}

/// UI-agnostic reversal of `FileChange`s. Never overwrites or permanently
/// deletes anything: a revert that would need to (the original spot has
/// been taken since) fails with a clear error instead.
struct FileUndoService {
    /// Reverts `changes` newest-first, so a batch unwinds in the opposite
    /// order it was made. `FileUndoResult.reverted` is itself in the order
    /// it was performed — reverting *that* (Redo) replays the original.
    func revert(_ changes: [FileChange]) async -> FileUndoResult {
        await Task.detached(priority: .userInitiated) {
            var reverted: [FileChange] = []
            for change in changes.reversed() {
                do {
                    reverted.append(try Self.revert(change))
                } catch {
                    return FileUndoResult(reverted: reverted, error: error)
                }
            }
            return FileUndoResult(reverted: reverted, error: nil)
        }.value
    }

    private static func revert(_ change: FileChange) throws -> FileChange {
        switch change {
        case .moved(let from, let to):
            try move(to, backTo: from)
            return .moved(from: to, to: from)

        case .created(let url):
            guard itemExists(at: url) else { throw FileUndoError.missing(url.lastPathComponent) }
            let trashedAt: URL?
            do {
                trashedAt = try Platform.trashItem(url)
            } catch {
                throw FileUndoError.failed(url.lastPathComponent, underlying: error)
            }
            return .trashed(original: url, trashedAt: trashedAt ?? url)

        case .trashed(let original, let trashedAt):
            try move(trashedAt, backTo: original)
            return .created(original)
        }
    }

    private static func move(_ current: URL, backTo original: URL) throws {
        guard itemExists(at: current) else { throw FileUndoError.missing(current.lastPathComponent) }
        // A case-only rename's two spellings are the same item on a
        // case-insensitive volume — that's not something in the way.
        let isCaseVariant = current.path.lowercased() == original.path.lowercased()
        guard isCaseVariant || !itemExists(at: original) else { throw FileUndoError.occupied(original.lastPathComponent) }
        do {
            try FileManager.default.moveItem(at: current, to: original)
        } catch {
            throw FileUndoError.failed(original.lastPathComponent, underlying: error)
        }
    }

    /// `fileExists(atPath:)` follows symlinks, so it reports a dangling
    /// link as missing — check the item itself instead.
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}
