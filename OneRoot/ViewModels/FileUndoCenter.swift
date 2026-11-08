import Foundation

/// App-wide Undo/Redo for file operations — one stack shared by every
/// window, like Finder's, rather than per window: tabs move between
/// windows, and "undo that move I just did" shouldn't depend on which
/// window happens to be in front.
///
/// Its own two stacks rather than Foundation's `UndoManager`, which Linux
/// doesn't have; the rules are `UndoManager`'s: up to 100 steps, Redo kept
/// until something new is done. On the Mac, Edit ▸ Undo/Redo (⌘Z / ⇧⌘Z)
/// reach it through `FileTableView` and `ContextMenuOutlineView`, which
/// route `undo:`/`redo:` here while they're first responder (see
/// FileUndoCenter+Menu.swift). Text fields keep their own typing undo,
/// since they're first responder while editing.
@MainActor
final class FileUndoCenter {
    static let shared = FileUndoCenter()

    static let levelsOfUndo = 100

    private struct Step {
        let box: ChangeBox
        let actionName: String
    }

    private var undoStack: [Step] = []
    private var redoStack: [Step] = []

    private let undoService: FileUndoService
    private let trashOriginService: TrashOriginService
    /// Injectable so tests don't put up alerts.
    private let presentError: @MainActor (String) -> Void

    init(
        undoService: FileUndoService = FileUndoService(),
        trashOriginService: TrashOriginService = TrashOriginService(),
        presentError: @escaping @MainActor (String) -> Void = { Platform.showError("Undo Failed", $0) }
    ) {
        self.undoService = undoService
        self.trashOriginService = trashOriginService
        self.presentError = presentError
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoActionName: String { undoStack.last?.actionName ?? "" }
    var redoActionName: String { redoStack.last?.actionName ?? "" }
    /// "Undo Rename", or just "Undo" — the Edit menu's wording.
    var undoMenuItemTitle: String { Self.menuTitle("Undo", undoActionName) }
    var redoMenuItemTitle: String { Self.menuTitle("Redo", redoActionName) }

    private static func menuTitle(_ verb: String, _ actionName: String) -> String {
        actionName.isEmpty ? verb : "\(verb) \(actionName)"
    }

    /// Makes `changes` undoable as one step, shown in the Edit menu as
    /// "Undo <actionName>". Call once the operation has finished — including
    /// when it failed or was cancelled partway, with whatever did complete.
    func record(_ changes: [FileChange], actionName: String) {
        guard !changes.isEmpty else { return }
        push(Step(box: ChangeBox(changes: changes), actionName: actionName), onto: &undoStack)
        redoStack.removeAll()
    }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        push(revert(step), onto: &redoStack)
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        push(revert(step), onto: &undoStack)
    }

    private func push(_ step: Step, onto stack: inout [Step]) {
        stack.append(step)
        if stack.count > Self.levelsOfUndo { stack.removeFirst(stack.count - Self.levelsOfUndo) }
    }

    /// The in-flight revert (if any), so tests can wait for an Undo/Redo
    /// to actually finish touching the disk.
    private(set) var pendingRevert: Task<Void, Never>?

    /// Returns the inverse step right away — so Undo then Redo works even
    /// before the disk has caught up — and fills its changes in once the
    /// revert finishes.
    private func revert(_ step: Step) -> Step {
        let box = step.box
        let inverse = ChangeBox(changes: [])
        let task = Task {
            // ⌘Z pressed twice quickly: let the previous step land first.
            await box.pending?.value
            let result = await undoService.revert(box.changes)
            inverse.changes = result.reverted
            updateTrashOrigins(reverting: box.changes, result: result.reverted)
            if let error = result.error {
                // The disk no longer matches what's on the stack, so
                // nothing older on it can be trusted to undo cleanly.
                undoStack.removeAll()
                redoStack.removeAll()
                presentError(error.localizedDescription)
            }
        }
        inverse.pending = task
        pendingRevert = task
        return Step(box: inverse, actionName: step.actionName)
    }

    /// Keeps Restore (see `TrashOriginService`) working for items Undo/Redo
    /// moves in and out of Trash.
    private func updateTrashOrigins(reverting changes: [FileChange], result reverted: [FileChange]) {
        for change in changes.reversed().prefix(reverted.count) {
            if case .trashed(_, let trashedAt) = change {
                trashOriginService.removeRecord(forTrashedURL: trashedAt)
            }
        }
        for change in reverted {
            if case .trashed(let original, let trashedAt) = change {
                trashOriginService.recordOrigin(trashedURL: trashedAt, originalURL: original)
            }
        }
    }

    /// "Copy of “notes.txt”" / "Copy of 3 Items" — Finder's phrasing.
    static func actionName(_ verb: String, items: [URL]) -> String {
        items.count == 1 ? "\(verb) of \u{201C}\(items[0].lastPathComponent)\u{201D}" : "\(verb) of \(items.count) Items"
    }
}

/// Reference box so a registered Undo/Redo can be handed changes that are
/// only known once an async revert finishes.
@MainActor
private final class ChangeBox {
    var changes: [FileChange]
    var pending: Task<Void, Never>?

    init(changes: [FileChange]) {
        self.changes = changes
    }
}
