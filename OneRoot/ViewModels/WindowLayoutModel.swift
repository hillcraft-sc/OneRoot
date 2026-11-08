import Foundation
import Observation

/// One window's pane layout (`WindowLayout`): which panes are shown and
/// their sizes. Owned by `WindowViewModel` so it's saved with the session.
///
/// Visibility and tool changes publish (the window re-lays out); size
/// changes from dragging a divider deliberately don't — the split view
/// already shows the new size, and re-rendering the whole window on every
/// pixel of a drag would be wasted work. Sizes are still stored, for the
/// session and for the next new window.
@MainActor
@Observable
final class WindowLayoutModel {
    /// Read through `layout`; written directly only for a size that
    /// shouldn't notify anyone.
    @ObservationIgnored private var storage: WindowLayout
    private(set) var layout: WindowLayout {
        get {
            access(keyPath: \.layout)
            return storage
        }
        set {
            withMutation(keyPath: \.layout) { storage = newValue }
        }
    }

    @ObservationIgnored private let service: WindowLayoutService?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    /// `service` is `nil` in tests, so they never write the real
    /// "last layout" default.
    init(layout: WindowLayout, service: WindowLayoutService? = nil) {
        self.storage = layout.clamped
        self.service = service
    }

    /// A visible change: publishes, then remembers the layout for new windows.
    func set<Value: Equatable>(_ keyPath: WritableKeyPath<WindowLayout, Value>, _ value: Value) {
        guard layout[keyPath: keyPath] != value else { return }
        layout[keyPath: keyPath] = value
        scheduleSave()
    }

    func toggle(_ keyPath: WritableKeyPath<WindowLayout, Bool>) {
        set(keyPath, !layout[keyPath: keyPath])
    }

    /// View ▸ Reset Window Layout: back to the default panes and sizes.
    func reset() {
        let defaults = WindowLayout()
        guard layout != defaults else { return }
        layout = defaults
        scheduleSave()
    }

    /// A size the user dragged to — stored without publishing (see the type
    /// comment). Clamped, so a pane collapsing mid-drag can't record zero.
    /// `publishes` for a size something else lines up with (the tab strip
    /// follows the destinations sidebar's width).
    func recordSize(_ keyPath: WritableKeyPath<WindowLayout, Double>, _ value: Double, publishes: Bool = false) {
        var updated = layout
        updated[keyPath: keyPath] = value
        let clamped = updated.clamped[keyPath: keyPath]
        guard storage[keyPath: keyPath] != clamped else { return }
        storage[keyPath: keyPath] = clamped
        scheduleSave()
        // Sizes arrive from the split view in the middle of a layout pass;
        // notifying right then is "publishing changes from within view
        // updates" and can feed back into the same layout.
        if publishes {
            DispatchQueue.main.async { [weak self] in
                self?.withMutation(keyPath: \.layout) {}
            }
        }
    }

    /// Coalesced: a divider drag reports many sizes a second.
    private func scheduleSave() {
        guard let service else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            service.save(self.layout)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

