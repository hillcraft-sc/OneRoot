import AppKit

/// Shared helpers for the file list's and sidebar tree's drag source/
/// destination implementations (`FileTableController`,
/// `FolderOutlineViewController`). Both drag real file `NSURL`s — existing
/// files already on disk, not generated content — so no
/// `NSFilePromiseProvider` is needed; a plain `NSURL` pasteboard writer is
/// enough, and it interoperates with Finder and other apps for free since
/// dragging goes through the system pasteboard, not app-internal state.
extension NSDraggingInfo {
    var draggedFileURLs: [URL]? {
        let urls = draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        return (urls?.isEmpty ?? true) ? nil : urls
    }
}

/// Rejects dropping a folder into itself or one of its own descendants —
/// `FileManager.moveItem`/`copyItem` would otherwise throw or, worse, appear
/// to succeed while doing something nonsensical.
func isValidDropTarget(_ target: URL, for draggedURLs: [URL]) -> Bool {
    !draggedURLs.contains { target.path == $0.path || target.path.hasPrefix($0.path + "/") }
}
