import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Drag and drop for files: what any widget needs to hand files out (a
/// `GdkFileList`, which GTK also offers other apps as `text/uri-list`) or to
/// take them in. The move-or-copy choice follows Nautilus and Dolphin: a
/// move when dragging within one filesystem, a copy across filesystems,
/// Ctrl forces a copy and Shift forces a move.
@MainActor
enum DragAndDrop {
    nonisolated(unsafe) static let copyAndMove = GdkDragAction(rawValue: GDK_ACTION_COPY.rawValue | GDK_ACTION_MOVE.rawValue)
    nonisolated(unsafe) static let none = GdkDragAction(rawValue: 0)

    // MARK: Policy

    /// Which single action a drag gets. `offered` is what the source allows.
    static func action(offered: GdkDragAction, sameFilesystem: Bool, control: Bool, shift: Bool) -> GdkDragAction {
        func allowed(_ action: GdkDragAction) -> Bool { offered.rawValue & action.rawValue != 0 }
        let wantsMove: Bool
        if control { wantsMove = false } else if shift { wantsMove = true } else { wantsMove = sameFilesystem }
        if wantsMove && allowed(GDK_ACTION_MOVE) { return GDK_ACTION_MOVE }
        if allowed(GDK_ACTION_COPY) { return GDK_ACTION_COPY }
        if allowed(GDK_ACTION_MOVE) { return GDK_ACTION_MOVE }
        return none
    }

    /// Whether `urls` and `folder` are on one filesystem (so moving is just a
    /// rename). A drop that can't be checked counts as a different one.
    static func sameFilesystem(_ urls: [URL], as folder: URL) -> Bool {
        var target = stat()
        guard !urls.isEmpty, stat(folder.path, &target) == 0 else { return false }
        for url in urls {
            var source = stat()
            guard stat(url.deletingLastPathComponent().path, &source) == 0, source.st_dev == target.st_dev else { return false }
        }
        return true
    }

    /// A folder can't be dropped into itself or something inside it.
    static func isDroppable(_ urls: [URL], into folder: URL) -> Bool {
        let destination = folder.standardizedFileURL.path
        return !urls.contains { url in
            let path = url.standardizedFileURL.path
            return destination == path || destination.hasPrefix(path == "/" ? "/" : path + "/")
        }
    }

    // MARK: Targets

    /// Takes files dropped on `widget` into the folder `destination` names
    /// (`nil` while there's no folder: Recents, the Trash). `highlight` is
    /// told when the pointer is over it with something droppable.
    static func attachFileTarget(
        to widget: Widget,
        destination: @escaping () -> URL?,
        highlight: @escaping (Bool) -> Void,
        drop: @escaping (_ urls: [URL], _ folder: URL, _ move: Bool) -> Void
    ) {
        attachTarget(to: widget, actions: copyAndMove, highlight: highlight, choose: { urls, offered, control, shift in
            guard let folder = destination(), !Platform.isTrashFolder(folder), isDroppable(urls, into: folder) else { return none }
            return action(offered: offered, sameFilesystem: sameFilesystem(urls, as: folder), control: control, shift: shift)
        }, drop: { urls, chosen in
            guard let folder = destination() else { return false }
            drop(urls, folder, chosen.rawValue == GDK_ACTION_MOVE.rawValue)
            return true
        })
    }

    /// The general target: `choose` returns the action to offer for the files
    /// (`none` rejects), `drop` receives them with that action.
    static func attachTarget(
        to widget: Widget,
        actions: GdkDragAction,
        highlight: @escaping (Bool) -> Void,
        choose: @escaping (_ urls: [URL], _ offered: GdkDragAction, _ control: Bool, _ shift: Bool) -> GdkDragAction,
        drop: @escaping (_ urls: [URL], _ action: GdkDragAction) -> Bool
    ) {
        let target = DropTarget.forFiles(actions: actions)
        target.preload = true
        let state = DropState()

        let decide: @MainActor (DropTarget) -> GdkDragAction = { target in
            let urls = target.droppedFiles
            guard !urls.isEmpty else { return none }
            var offered = actions
            if let current = gtk_drop_target_get_current_drop(target.opaquePointer) {
                offered = GdkDragAction(rawValue: gdk_drop_get_actions(current).rawValue & actions.rawValue)
            }
            let modifiers = gtk_event_controller_get_current_event_state(OpaquePointer(target.pointer)).rawValue
            let chosen = choose(urls, offered, modifiers & GDK_CONTROL_MASK.rawValue != 0, modifiers & GDK_SHIFT_MASK.rawValue != 0)
            state.action = chosen
            highlight(chosen.rawValue != 0)
            return chosen
        }
        target.onEnter(preferredAction: { [weak target] _, _ in target.map(decide) ?? none })
        target.onMotion(preferredAction: { [weak target] _, _ in target.map(decide) ?? none })
        target.onLeave { highlight(false) }
        target.onDropFiles { urls in
            highlight(false)
            guard state.action.rawValue != 0 else { return false }
            return drop(urls, state.action)
        }
        widget.addController(target)
    }

    private final class DropState {
        var action = DragAndDrop.none
    }

    // MARK: Sources

    /// Lets `widget` be dragged, carrying the files `urls` returns when the
    /// drag starts (an empty list cancels it).
    static func attachSource(to widget: Widget, urls: @escaping @MainActor () -> [URL]) {
        let source = DragSource()
        source.actions = copyAndMove
        let box = Unmanaged.passRetained(PrepareBox(urls))
        let prepare: @convention(c) (UnsafeMutableRawPointer?, Double, Double, UnsafeMutableRawPointer?) -> UnsafeMutablePointer<GdkContentProvider>? = { _, _, _, data in
            guard let data else { return nil }
            let box = Unmanaged<PrepareBox>.fromOpaque(data).takeUnretainedValue()
            return MainActor.assumeIsolated { DragAndDrop.provider(for: box.urls()) }
        }
        let release: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
            if let data { Unmanaged<PrepareBox>.fromOpaque(data).release() }
        }
        g_signal_connect_data(UnsafeMutableRawPointer(source.opaquePointer), "prepare", unsafeBitCast(prepare, to: GCallback.self), box.toOpaque(), unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        widget.addController(source)
    }

    private final class PrepareBox {
        let urls: @MainActor () -> [URL]
        init(_ urls: @escaping @MainActor () -> [URL]) { self.urls = urls }
    }

    private static func provider(for urls: [URL]) -> UnsafeMutablePointer<GdkContentProvider>? {
        guard !urls.isEmpty else { return nil }
        var list: UnsafeMutablePointer<GSList>?
        for url in urls.reversed() {
            guard let file = g_file_new_for_path(url.path) else { continue }
            list = g_slist_prepend(list, UnsafeMutableRawPointer(file))
        }
        defer { g_slist_free_full(list) { if let file = $0 { g_object_unref(file) } } }
        var value = GValue()
        g_value_init(&value, gdk_file_list_get_type())
        defer { g_value_unset(&value) }
        g_value_set_boxed(&value, list)
        return gdk_content_provider_new_for_value(&value)
    }
}
