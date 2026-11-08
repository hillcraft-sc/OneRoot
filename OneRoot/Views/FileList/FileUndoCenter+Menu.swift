import AppKit

/// The Mac's Edit ▸ Undo/Redo for `FileUndoCenter`: the views that route
/// `undo:`/`redo:` to it ask here to enable and title the menu items.
extension FileUndoCenter {
    /// Enables and titles Undo/Redo, or returns `nil` for any other menu
    /// item so the caller falls back to its usual answer.
    func validate(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(UndoActionResponder.undo(_:)):
            menuItem.title = undoMenuItemTitle
            return canUndo
        case #selector(UndoActionResponder.redo(_:)):
            menuItem.title = redoMenuItemTitle
            return canRedo
        default:
            return nil
        }
    }
}

/// Only here to name the standard `undo:`/`redo:` selectors for
/// `#selector` — AppKit declares them informally, on no public type.
@objc protocol UndoActionResponder {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}
