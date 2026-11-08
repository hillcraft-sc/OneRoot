import Foundation

/// What `FileSystemService.moveToTrash` managed: the items now in the
/// Trash (with where, when the system said), and the ones it couldn't move.
struct TrashResult {
    var trashed: [URL] = []
    var locations: [URL: URL] = [:]
    var failures: [(url: URL, error: Error)] = []

    /// The failed items whose volume has no Trash at all (NFS/SMB shares
    /// and the like) — the only way to remove those is to delete them for
    /// good, which callers offer after asking.
    var withoutTrash: [URL] {
        failures.filter { FileSystemError.isTrashUnsupported($0.error) }.map(\.url)
    }

    /// This result with `urls` no longer counted as failures — once they've
    /// been dealt with some other way.
    func removingFailures(_ urls: [URL]) -> TrashResult {
        var result = self
        let handled = Set(urls)
        result.failures.removeAll { handled.contains($0.url) }
        return result
    }
}

enum FileSystemError: LocalizedError {
    case cannotList(URL, underlying: Error)
    case alreadyExists(String)
    case cannotRename(String, underlying: Error)
    case cannotCreateFolder(String, underlying: Error)
    case cannotCreateFile(String, underlying: Error)
    case cannotTrash(URL, underlying: Error)
    case cannotCopy(String, underlying: Error)
    case cannotMove(String, underlying: Error)
    case cannotRestore(URL, underlying: Error)
    case cannotDeletePermanently(URL, underlying: Error)
    case cannotPlaceInsideItself(String)
    case cannotReplaceContainingItem(String)
    case cannotReplace(String, underlying: Error)
    case cannotMakeAlias(String, underlying: Error)

    /// The system error behind this one, if there is one.
    var underlyingError: Error? {
        switch self {
        case .cannotList(_, let underlying), .cannotRename(_, let underlying),
             .cannotCreateFolder(_, let underlying), .cannotCreateFile(_, let underlying),
             .cannotTrash(_, let underlying), .cannotCopy(_, let underlying),
             .cannotMove(_, let underlying), .cannotRestore(_, let underlying),
             .cannotDeletePermanently(_, let underlying), .cannotReplace(_, let underlying),
             .cannotMakeAlias(_, let underlying):
            return underlying
        case .alreadyExists, .cannotPlaceInsideItself, .cannotReplaceContainingItem:
            return nil
        }
    }

    /// Whether `error` is `trashItem` reporting that the item's volume
    /// doesn't have a Trash.
    static func isTrashUnsupported(_ error: Error) -> Bool {
        let underlying = (error as? FileSystemError)?.underlyingError ?? error
        let nsError = underlying as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFeatureUnsupportedError
    }

    /// Whether `error` says the file or folder isn't there (a Trash folder
    /// that was never created, say).
    static func isMissing(_ error: Error) -> Bool {
        let underlying = (error as? FileSystemError)?.underlyingError ?? error
        let nsError = underlying as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }

    var errorDescription: String? {
        switch self {
        case .cannotList(let url, let underlying):
            return "Can't read \(url.path): \(underlying.localizedDescription)"
        case .alreadyExists(let name):
            return "\"\(name)\" already exists here."
        case .cannotRename(let name, let underlying):
            return "Can't rename to \"\(name)\": \(underlying.localizedDescription)"
        case .cannotCreateFolder(let name, let underlying):
            return "Can't create \"\(name)\": \(underlying.localizedDescription)"
        case .cannotCreateFile(let name, let underlying):
            return "Can't create \"\(name)\": \(underlying.localizedDescription)"
        case .cannotTrash(let url, let underlying):
            return "Can't move \"\(url.lastPathComponent)\" to Trash: \(underlying.localizedDescription)"
        case .cannotCopy(let name, let underlying):
            return "Can't copy \"\(name)\": \(underlying.localizedDescription)"
        case .cannotMove(let name, let underlying):
            return "Can't move \"\(name)\": \(underlying.localizedDescription)"
        case .cannotRestore(let url, let underlying):
            return "Can't restore \"\(url.lastPathComponent)\": \(underlying.localizedDescription)"
        case .cannotDeletePermanently(let url, let underlying):
            return "Can't delete \"\(url.lastPathComponent)\": \(underlying.localizedDescription)"
        case .cannotPlaceInsideItself(let name):
            return "Can't put \"\(name)\" inside itself."
        case .cannotReplaceContainingItem(let name):
            return "Can't replace \"\(name)\" because it contains the item being copied or moved."
        case .cannotReplace(let name, let underlying):
            return "Can't replace \"\(name)\": \(underlying.localizedDescription)"
        case .cannotMakeAlias(let name, let underlying):
            return "Can't make an alias to \"\(name)\": \(underlying.localizedDescription)"
        }
    }
}
