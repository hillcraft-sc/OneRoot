import Foundation

/// One reversible change a file operation made — the unit Undo/Redo works
/// in (see `FileUndoService`). Every operation OneRoot can undo reduces to
/// these three, and each one's inverse is again one of them:
///
/// - `moved` (move, cut/paste, rename, restore) ↔ `moved` back
/// - `created` (copy, new folder/file, undoing a trash) → `trashed`
/// - `trashed` (move to Trash, undoing a create) → `created`
///
/// Undoing a copy trashes the copy rather than deleting it, so Redo is just
/// putting it back — and nothing Undo does is ever unrecoverable.
enum FileChange: Equatable {
    case moved(from: URL, to: URL)
    case created(URL)
    case trashed(original: URL, trashedAt: URL)
}
