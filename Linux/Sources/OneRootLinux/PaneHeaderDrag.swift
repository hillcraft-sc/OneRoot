import Adwaita
import CAdwaita
import Foundation

/// Drag a Dual Pane header onto the other pane to swap the two sides (the
/// Mac's pane drag). The header is the drag handle; the whole other pane is
/// the target. The payload is only a marker string: which pane is being
/// dragged is held here while the drag lasts.
@MainActor
enum PaneHeaderDrag {
    private static let marker = "oneroot-pane"
    private static var dragging: ObjectIdentifier?

    /// `pane` identifies the pane under `header`; `target` is the widget that
    /// takes a drop (that pane's whole box); `onSwap` runs on a drop from the
    /// other pane.
    static func attach(header: Widget, target: Widget, pane: AnyObject, onSwap: @escaping @MainActor () -> Void, onDragOut: @escaping @MainActor () -> Void) {
        let id = ObjectIdentifier(pane)

        let source = DragSource()
        source.actions = GDK_ACTION_MOVE
        let prepare: @convention(c) (UnsafeMutableRawPointer?, Double, Double, UnsafeMutableRawPointer?) -> UnsafeMutablePointer<GdkContentProvider>? = { _, _, _, data in
            guard let data else { return nil }
            let owner = Unmanaged<Token>.fromOpaque(data).takeUnretainedValue()
            return MainActor.assumeIsolated {
                PaneHeaderDrag.dragging = owner.id
                var value = GValue()
                g_value_init(&value, g_type_from_name("gchararray"))
                defer { g_value_unset(&value) }
                g_value_set_string(&value, PaneHeaderDrag.marker)
                return gdk_content_provider_new_for_value(&value)
            }
        }
        let release: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
            if let data { Unmanaged<Token>.fromOpaque(data).release() }
        }
        let token = Unmanaged.passRetained(Token(id))
        g_signal_connect_data(UnsafeMutableRawPointer(source.opaquePointer), "prepare", unsafeBitCast(prepare, to: GCallback.self),
                              token.toOpaque(), unsafeBitCast(release, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        // drag-end has three arguments; the binding's typed handler takes two.
        let ended: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?) -> Void = { _, _, _, _ in
            MainActor.assumeIsolated { PaneHeaderDrag.dragging = nil }
        }
        g_signal_connect_data(UnsafeMutableRawPointer(source.opaquePointer), "drag-end", unsafeBitCast(ended, to: GCallback.self),
                              nil, nil, GConnectFlags(rawValue: 0))
        // Dropped where nothing takes it (reason NO_TARGET = 2): pop the pane
        // out into its own window. Esc (USER_CANCELLED) does nothing.
        let cancelled: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?) -> Int32 = { _, _, reason, data in
            guard let data, reason == 2 else { return 0 }
            let handler = Unmanaged<DragOutHandler>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                PaneHeaderDrag.dragging = nil
                handler.run()
            }
            return 1
        }
        let outRelease: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, _ in
            if let data { Unmanaged<DragOutHandler>.fromOpaque(data).release() }
        }
        let out = Unmanaged.passRetained(DragOutHandler(onDragOut))
        g_signal_connect_data(UnsafeMutableRawPointer(source.opaquePointer), "drag-cancel", unsafeBitCast(cancelled, to: GCallback.self),
                              out.toOpaque(), unsafeBitCast(outRelease, to: GClosureNotify.self), GConnectFlags(rawValue: 0))
        header.addController(source)

        let drop = DropTarget.forText(actions: GDK_ACTION_MOVE)
        drop.onDrop { text in
            defer { dragging = nil }
            guard text == marker, let from = dragging, from != id else { return false }
            onSwap()
            return true
        }
        target.addController(drop)
    }

    private final class DragOutHandler {
        let run: @MainActor () -> Void
        init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    }

    private final class Token {
        let id: ObjectIdentifier
        init(_ id: ObjectIdentifier) { self.id = id }
    }
}
