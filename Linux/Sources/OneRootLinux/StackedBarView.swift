import Adwaita
import CAdwaita
import Foundation

/// The stacked bar over Types, Age, Tags and Cloud: one segment per group,
/// width proportional to size, in the groups' fixed order and colors. A
/// segment click chooses that group. The list beside it carries the same
/// numbers as text.
@MainActor
final class StackedBarView {
    struct Segment {
        let id: String
        let size: Int64
        let className: String
        let tooltip: String
    }

    /// A scroller that never scrolls, so segment size requests don't hold the
    /// bar at its widest (see `TreemapView`).
    let widget: ScrolledWindow
    private let surface: Widget
    private let fixed: UnsafeMutablePointer<GtkFixed>
    private var segments: [Segment] = []
    private var current: String?
    private var buttons: [Button] = []
    private var laidOutWidth = 0
    var onChoose: ((String) -> Void)?

    init() {
        let raw = gtk_fixed_new()!
        fixed = UnsafeMutablePointer<GtkFixed>(OpaquePointer(raw))
        surface = Widget(raw: UnsafeMutableRawPointer(raw))
        widget = ScrolledWindow(child: surface)
        gtk_scrolled_window_set_policy(widget.opaquePointer, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        widget.hexpand = true
        widget.setSizeRequest(width: 100, height: 14)
        widget.setAccessibleLabel("Stacked bar of the groups")
        watchWidth()
    }

    func set(_ segments: [Segment], current: String?) {
        self.segments = segments
        self.current = current
        for button in buttons { gtk_fixed_remove(fixed, button.widgetPointer) }
        buttons = segments.map { segment in
            let button = Button()
            button.addCSSClass("oneroot-stacked-segment")
            button.addCSSClass(segment.className)
            if segment.id != current { button.addCSSClass("oneroot-stacked-dim") }
            button.tooltipText = segment.tooltip
            button.setAccessibleLabel(segment.tooltip)
            button.onClicked { [weak self] in self?.onChoose?(segment.id) }
            gtk_fixed_put(fixed, button.widgetPointer, 0, 0)
            return button
        }
        laidOutWidth = 0
        layout()
    }

    /// Segment widths for `sizes` across `width` points with `gap` between
    /// them: proportional, and at least 2 for anything that has size.
    nonisolated static func widths(for sizes: [Int64], in width: Double, gap: Double = 2) -> [Double] {
        let total = Double(sizes.reduce(0) { $0 + max($1, 0) })
        guard total > 0 else { return sizes.map { _ in 0 } }
        let usable = max(width - gap * Double(max(sizes.count - 1, 0)), 0)
        return sizes.map { $0 > 0 ? max(usable * Double($0) / total, 2) : 0 }
    }

    private func layout() {
        let width = widget.width
        guard width > 0, !segments.isEmpty, laidOutWidth != width else { return }
        laidOutWidth = width
        let widths = Self.widths(for: segments.map(\.size), in: Double(width))
        var x = 0.0
        for (index, button) in buttons.enumerated() {
            let segmentWidth = widths[index]
            button.visible = segmentWidth > 0
            guard segmentWidth > 0 else { continue }
            button.setSizeRequest(width: Int(segmentWidth.rounded()), height: 14)
            gtk_fixed_move(fixed, button.widgetPointer, x, 0)
            x += segmentWidth + 2
        }
    }

    private func watchWidth() {
        final class Ref { weak var view: StackedBarView? }
        let ref = Ref()
        ref.view = self
        gtk_widget_add_tick_callback(widget.widgetPointer, { _, _, data in
            guard let data else { return gboolean(0) }
            let ref = Unmanaged<Ref>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { ref.view?.layout() }
            return ref.view == nil ? gboolean(0) : gboolean(1)
        }, Unmanaged.passRetained(ref).toOpaque(), { data in
            if let data { Unmanaged<Ref>.fromOpaque(data).release() }
        })
    }
}
