import Foundation

/// The Move to Trash confirmation, asked by every UI entry point that can
/// trigger it (`FileTableController`'s ⌫/context menu, `FolderOutlineView`'s
/// context menu, the toolbar's Trash button) rather than inside the view
/// models, whose tests would otherwise hang on a modal that never appears.
/// The prompts themselves are `Platform`'s.
@MainActor
enum TrashConfirmation {
    /// `true` means proceed.
    static func confirm(_ names: [String]) -> Bool {
        Platform.confirmTrash(names)
    }

    /// For items on a volume with no Trash: asks again, since the only way
    /// to remove them is to delete them for good. `true` means delete.
    static func confirmDeleteWithoutTrash(_ urls: [URL]) -> Bool {
        Platform.confirmDeleteWithoutTrash(urls)
    }
}
