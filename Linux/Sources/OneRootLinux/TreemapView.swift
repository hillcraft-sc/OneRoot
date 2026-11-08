import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Folders treemap: one block per item, area proportional to size, laid
/// out by the shared `TreemapLayout` and re-laid out whenever the widget's
/// size changes. Folders are accent-colored, files gray, "Other" paler.
/// Blocks are buttons (click = the same action as the list beside it); the
/// list carries the accessible text, so the blocks hide from assistive tech
/// except for their label.
@MainActor
final class TreemapView {
    /// What goes in the layout: a scroller (never actually scrolling), so the
    /// blocks' own size requests don't hold the treemap at its largest size.
    let widget: ScrolledWindow
    private let surface: Widget
    private let fixed: UnsafeMutablePointer<GtkFixed>
    private var blocks: [TreemapBlocks.Block] = []
    private var total: Int64 = 0
    private var buttons: [Button] = []
    private var laidOutSize = (width: 0, height: 0)
    var onChoose: ((TreemapBlocks.Block) -> Void)?

    init() {
        let raw = gtk_fixed_new()!
        fixed = UnsafeMutablePointer<GtkFixed>(OpaquePointer(raw))
        surface = Widget(raw: UnsafeMutableRawPointer(raw))
        widget = ScrolledWindow(child: surface)
        gtk_scrolled_window_set_policy(widget.opaquePointer, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        widget.hexpand = true
        widget.vexpand = true
        widget.setSizeRequest(width: 200, height: 120)
        widget.addCSSClass("oneroot-treemap")
        widget.setAccessibleLabel("Treemap of the folder\u{2019}s items")
        watchSize()
    }

    func set(_ blocks: [TreemapBlocks.Block], total: Int64) {
        self.blocks = blocks
        self.total = total
        rebuild()
    }

    // MARK: Layout

    private func rebuild() {
        for button in buttons { gtk_fixed_remove(fixed, button.widgetPointer) }
        buttons = []
        for block in blocks {
            let button = Button()
            button.addCSSClass("oneroot-treemap-block")
            button.addCSSClass(block.entry == nil ? "oneroot-treemap-other" : (block.isFolder ? "oneroot-treemap-folder" : "oneroot-treemap-file"))
            button.tooltipText = "\(block.title) \u{2014} \(Formatting.size(block.size)) (\(TreemapBlocks.percent(block.size, of: total)))"
            button.setAccessibleLabel(button.tooltipText ?? block.title)
            button.sensitive = block.entry != nil
            button.onClicked { [weak self] in self?.onChoose?(block) }
            gtk_fixed_put(fixed, button.widgetPointer, 0, 0)
            buttons.append(button)
        }
        laidOutSize = (0, 0)
        layout()
    }

    private func layout() {
        let width = widget.width
        let height = widget.height
        // Positioning needs the surface to be at least as big as the area.
        surface.setSizeRequest(width: 1, height: 1)
        guard width > 0, height > 0, !blocks.isEmpty, laidOutSize != (width, height) else { return }
        laidOutSize = (width, height)
        let rects = TreemapLayout.rects(for: blocks.map { Double($0.size) }, in: CGRect(x: 0, y: 0, width: width, height: height))
        for (index, button) in buttons.enumerated() {
            let rect = rects[index].insetBy(dx: 1, dy: 1)
            guard rect.width > 1, rect.height > 1 else { button.visible = false; continue }
            button.visible = true
            button.setSizeRequest(width: Int(rect.width), height: Int(rect.height))
            gtk_fixed_move(fixed, button.widgetPointer, rect.minX, rect.minY)
            setLabel(button, blocks[index], width: rect.width, height: rect.height)
        }
    }

    /// A name and size inside blocks big enough to read them.
    private func setLabel(_ button: Button, _ block: TreemapBlocks.Block, width: CGFloat, height: CGFloat) {
        guard width > 56, height > 30 else { button.child = nil; return }
        let name = Label(block.title)
        name.xalign = 0
        name.ellipsize = PANGO_ELLIPSIZE_END
        name.addCSSClass("caption-heading")
        name.addCSSClass("oneroot-treemap-text")
        let size = Label("")
        size.markup = "<small>\(Formatting.size(block.size))</small>"
        size.xalign = 0
        size.addCSSClass("oneroot-treemap-text")
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 1)
        box.halign = GTK_ALIGN_START
        box.valign = GTK_ALIGN_START
        box.append(name)
        box.append(size)
        button.child = box
    }

    /// Re-lays out when the widget's size changes (checked once per frame:
    /// a pair of integer compares unless it did).
    private func watchSize() {
        final class Ref { weak var view: TreemapView? }
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
