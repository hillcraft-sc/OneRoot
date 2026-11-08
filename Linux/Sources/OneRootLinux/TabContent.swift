import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// What one tab shows: its file list, or two side by side in Dual Pane.
/// The panes are made by the window (it wires their menus and opening).
@MainActor
final class TabContent {
    let tab: Tab
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private(set) var primary: FileListPane
    private(set) var secondary: FileListPane?
    private let makePane: (FileListViewModel) -> FileListPane
    private var watches: [ObservationWatch] = []
    private var headerWatches: [ObservationWatch] = []
    private var paned: Paned?
    private var compareBar: CompareBar?
    /// Compare Panes' bar sits above the panes; the panes keep their layout.
    private let barSlot = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private let body = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    /// What the Copy to Left/Right preview attaches to.
    var dialogParent: () -> Widget? = { nil }
    /// A pane header was dragged off the window: the window pops that pane out.
    var onPopOut: (Pane) -> Void = { _ in }

    init(tab: Tab, makePane: @escaping (FileListViewModel) -> FileListPane) {
        self.tab = tab
        self.makePane = makePane
        primary = makePane(tab.primary)
        widget.vexpand = true
        body.vexpand = true
        body.hexpand = true
        widget.append(barSlot)
        widget.append(body)
        widget.hexpand = true
        watches.append(ObservationWatch.watch({ (ObjectIdentifier(tab.primary), tab.secondary.map(ObjectIdentifier.init)) }) { [weak self] _ in
            self?.rebuild()
        })
        watches.append(ObservationWatch.watch({ tab.comparison.map(ObjectIdentifier.init) }) { [weak self] _ in
            self?.syncCompareBar()
        })
        watches.append(ObservationWatch.watch({ tab.focusedPane }) { [weak self] _ in
            self?.showFocus()
        })
    }

    var panes: [FileListPane] { [primary] + (secondary.map { [$0] } ?? []) }

    var focusedPane: FileListPane {
        tab.focusedPane == .secondary ? (secondary ?? primary) : primary
    }

    func pane(for viewModel: FileListViewModel) -> FileListPane? {
        panes.first { $0.viewModel === viewModel }
    }

    private func syncCompareBar() {
        while let child = barSlot.firstChild { barSlot.remove(child) }
        compareBar = nil
        guard tab.isSplit, let comparison = tab.comparison else { return }
        let bar = CompareBar(comparison: comparison) { [weak self] in self?.dialogParent() }
        compareBar = bar
        barSlot.append(bar.widget)
    }

    private func rebuild() {
        let existing = Dictionary(panes.map { (ObjectIdentifier($0.viewModel), $0) }, uniquingKeysWith: { a, _ in a })
        primary = existing[ObjectIdentifier(tab.primary)] ?? makePane(tab.primary)
        secondary = tab.secondary.map { existing[ObjectIdentifier($0)] ?? makePane($0) }
        headerWatches = []
        // Take the panes out of the old layout before building the new one.
        if let paned {
            paned.startChild = nil
            paned.endChild = nil
        }
        while let child = body.firstChild { body.remove(child) }
        paned = nil
        if let secondary {
            let split = Paned(orientation: GTK_ORIENTATION_HORIZONTAL, start: headed(primary), end: headed(secondary))
            split.wideHandle = true
            split.resizeStartChild = true
            split.resizeEndChild = true
            split.vexpand = true
            body.append(split)
            paned = split
            MainContext.task { [weak split] in
                // A tab that isn't showing yet (a restored session's background
                // tab) has no width: a position of 0 would collapse the first pane.
                guard let split, split.width > 0 else { return }
                split.position = split.width / 2
            }
        } else {
            body.append(primary.widget)
        }
        showFocus()
    }

    /// A pane under a header strip: its folder's name, and a Swap Panes button.
    /// Rebuilt with the panes, so the title watch lives on the pane's box.
    private func headed(_ pane: FileListPane) -> Box {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        box.hexpand = true
        box.vexpand = true
        let header = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        header.addCSSClass("oneroot-pane-header")
        header.marginStart = 10
        header.marginEnd = 6
        header.marginTop = 2
        header.marginBottom = 2
        let title = Label("")
        title.hexpand = true
        title.halign = GTK_ALIGN_START
        title.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        title.addCSSClass(.heading)
        let swap = Button(iconName: "object-flip-horizontal-symbolic")
        swap.addCSSClass(.flat)
        swap.tooltipText = "Swap Panes (Ctrl+Shift+\\)"
        swap.setAccessibleLabel("Swap panes")
        gtk_actionable_set_action_name(OpaquePointer(swap.pointer), "win.swap-panes")
        header.append(title)
        header.append(swap)
        box.append(header)
        box.append(pane.widget)
        PaneHeaderDrag.attach(header: header, target: box, pane: pane) { [weak box] in
            if let box { _ = gtk_widget_activate_action_variant(box.widgetPointer, "win.swap-panes", nil) }
        } onDragOut: { [weak self] in
            guard let self, self.tab.isSplit else { return }
            self.onPopOut(pane === self.primary ? .primary : .secondary)
        }
        let model = pane.viewModel
        let name = { (url: URL?) in url.map { $0.lastPathComponent.isEmpty ? "/" : $0.lastPathComponent } ?? "" }
        title.text = name(model.currentLocationURL)
        headerWatches.append(ObservationWatch.watch({ model.currentLocationURL }) { [weak title] url in
            title?.text = name(url)
        })
        return box
    }

    /// In Dual Pane the focused side gets an accent edge.
    private func showFocus() {
        for pane in panes {
            if tab.isSplit && pane === focusedPane {
                pane.widget.addCSSClass("oneroot-focused-pane")
            } else {
                pane.widget.removeCSSClass("oneroot-focused-pane")
            }
        }
    }
}
