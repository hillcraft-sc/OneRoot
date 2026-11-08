import AppKit
import SwiftUI

/// Side-by-side panes in a real `NSSplitViewController`, not SwiftUI's
/// `HSplitView`. `HSplitView` is itself backed by an `NSSplitViewController`
/// on this system — confirmed by the crash that came from trying to replace
/// its delegate (`NSInternalInconsistencyException: A SplitView managed by
/// a SplitViewController cannot have its delegate modified`). SwiftUI never
/// exposes that controller, so its initial widths got silently ignored.
/// Owning the controller directly gives full, sanctioned control over each
/// pane's sizing via `NSSplitViewItem` — the same mechanism Xcode's own
/// navigator/inspector panes use.
///
/// One pane is the flexible one (`width == nil`, e.g. the file list); the
/// rest have a remembered width, can be collapsed from SwiftUI
/// (`isCollapsed`), and report the width the user drags them to
/// (`onWidthChange`). Dragging a divider all the way in collapses a pane
/// too, the native way; that's reported (`onUserCollapse`) so the layout
/// model, which owns what's shown, can catch up.
struct PaneSplitView: NSViewControllerRepresentable {
    struct Pane {
        let content: AnyView
        let minWidth: CGFloat
        var maxWidth: CGFloat = NSSplitViewItem.unspecifiedDimension
        /// `nil` for the flexible pane; otherwise the width to show it at.
        var width: CGFloat?
        var isCollapsed = false
        /// Higher holds its size when the window resizes. All stay below
        /// AppKit's `.dragThatCannotResizeWindow` (490), the priority a
        /// divider drag itself operates at — above it, "hold your size"
        /// would beat the user's own drag and block resizing the pane.
        var holdingPriority: Float = 250
        var onWidthChange: ((CGFloat) -> Void)?
        var onUserCollapse: (() -> Void)?
    }

    let panes: [Pane]
    /// Invisible dividers (still draggable) — for cards that float apart
    /// on the window backdrop, where a drawn line would cut through the gap.
    var transparentDividers = false

    func makeNSViewController(context: Context) -> PaneSplitViewController {
        let controller = PaneSplitViewController()
        if transparentDividers {
            let splitView = TransparentDividerSplitView()
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            controller.splitView = splitView
        }
        for pane in panes {
            let hosting = NSHostingController(rootView: pane.content)
            // The split view sizes the panes; the hosted SwiftUI content
            // mustn't push back with its own ideal size.
            hosting.sizingOptions = []
            let item = NSSplitViewItem(viewController: hosting)
            item.minimumThickness = pane.minWidth
            item.maximumThickness = pane.maxWidth
            item.holdingPriority = NSLayoutConstraint.Priority(pane.holdingPriority)
            item.canCollapse = pane.width != nil
            // Narrow windows are handled by `WindowLayout.fitted(to:)`,
            // which knows which pane should give way first.
            item.canCollapseFromWindowResize = false
            item.isCollapsed = pane.isCollapsed
            controller.addSplitViewItem(item)
        }
        controller.panes = panes
        controller.observeCollapsing()
        return controller
    }

    func updateNSViewController(_ controller: PaneSplitViewController, context: Context) {
        controller.update(panes)
    }
}

final class PaneSplitViewController: NSSplitViewController {
    fileprivate(set) var panes: [PaneSplitView.Pane] = []
    private var didApplyInitialWidths = false
    /// Set while this controller moves dividers itself, so those moves
    /// aren't reported back as the user's chosen widths.
    private var isApplyingChange = false
    /// Panes mid-way through an animated collapse — their shrinking widths
    /// aren't the user's choice either.
    private var collapsingIndices: Set<Int> = []
    private var collapseObservations: [NSKeyValueObservation] = []
    /// The split view's width the last time panes were restored — they're
    /// only adjusted again once it changes. Adjusting runs inside layout,
    /// and moving a divider lays out again: a pane that can't reach its
    /// width (another pane's minimum is in the way) would otherwise retry
    /// forever, which AppKit stops by crashing the app.
    private var lastRestoredForWidth: CGFloat = -1
    private var settleRetries = 0

    /// Reports a pane the user collapsed by dragging its divider. Deferred
    /// a tick: it lands in SwiftUI state, which mustn't change mid-update.
    fileprivate func observeCollapsing() {
        collapseObservations = splitViewItems.enumerated().map { index, item in
            item.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
                // Only a divider the user dragged shut counts. AppKit also
                // collapses panes by itself while a window is first laid
                // out too small — taking that as the user's choice once
                // turned the Inspector off for good.
                let type = NSApp.currentEvent?.type
                guard type == .leftMouseDragged || type == .leftMouseUp else { return }
                DispatchQueue.main.async {
                    guard let self, index < self.panes.count,
                          item.isCollapsed, !self.panes[index].isCollapsed else { return }
                    self.panes[index].onUserCollapse?()
                }
            }
        }
    }

    func update(_ newPanes: [PaneSplitView.Pane]) {
        let previous = panes
        panes = newPanes
        for (index, pane) in newPanes.enumerated() where index < splitViewItems.count {
            let item = splitViewItems[index]
            (item.viewController as? NSHostingController<AnyView>)?.rootView = pane.content
            // Can change with what's shown inside (the main pane's minimum
            // grows with the hierarchy and Inspector beside the list).
            if item.minimumThickness != pane.minWidth { item.minimumThickness = pane.minWidth }
            guard index < previous.count, previous[index].isCollapsed != pane.isCollapsed else { continue }
            // On the next run-loop turn: this runs inside SwiftUI's view
            // update, and collapsing or expanding an item lays out the split
            // view — and the SwiftUI views hosted in it — reentrantly, which
            // makes SwiftUI skip that layout pass. That once left the Context
            // Bar missing everything right of New until something re-laid it.
            DispatchQueue.main.async { [weak self] in
                guard let self, index < self.panes.count, index < self.splitViewItems.count,
                      self.panes[index].isCollapsed == pane.isCollapsed,
                      self.splitViewItems[index].isCollapsed != pane.isCollapsed else { return }
                self.setCollapsed(pane.isCollapsed, itemAt: index)
            }
        }
    }

    private func setCollapsed(_ collapsed: Bool, itemAt index: Int) {
        let item = splitViewItems[index]
        isApplyingChange = true
        defer { isApplyingChange = false }
        if collapsed {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                item.isCollapsed = true
            } else {
                collapsingIndices.insert(index)
                NSAnimationContext.runAnimationGroup { _ in
                    item.animator().isCollapsed = true
                } completionHandler: { [weak self] in
                    self?.collapsingIndices.remove(index)
                }
            }
        } else {
            // Not animated: the pane has to come back at its remembered
            // width, which means placing the divider once it's laid out.
            item.isCollapsed = false
            splitView.layoutSubtreeIfNeeded()
            applyWidth(ofPaneAt: index)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard splitView.frame.width > 0 else { return }
        guard !didApplyInitialWidths else {
            restoreSqueezedPanes()
            return
        }
        didApplyInitialWidths = true
        isApplyingChange = true
        defer { isApplyingChange = false }
        for index in panes.indices where !panes[index].isCollapsed {
            applyWidth(ofPaneAt: index)
        }
    }

    /// Keeps each sized pane at its remembered width as the window changes:
    /// a pane squeezed smaller (the window was too narrow) grows back once
    /// the flexible pane has room to spare, and one that ended up wider
    /// gives the room back to the flexible pane.
    private func restoreSqueezedPanes() {
        let width = splitView.bounds.width
        guard abs(width - lastRestoredForWidth) > 0.5 else { return }
        // The first pass at a new width can still carry the old frames;
        // wait for the pass where the panes actually fill the split view.
        let shown = splitViewItems.filter { !$0.isCollapsed }
        let filled = shown.reduce(0) { $0 + $1.viewController.view.frame.width }
            + CGFloat(max(shown.count - 1, 0)) * splitView.dividerThickness
        guard abs(filled - width) < 2 else {
            // Hosted panes can settle just after the layout pass that
            // resized them; look again then (a few times at most).
            if settleRetries < 3 {
                settleRetries += 1
                DispatchQueue.main.async { [weak self] in self?.restoreSqueezedPanes() }
            }
            return
        }
        settleRetries = 0
        lastRestoredForWidth = width
        guard !isApplyingChange, NSApp.currentEvent?.type != .leftMouseDragged || splitView.inLiveResize,
              let flexibleIndex = panes.firstIndex(where: { $0.width == nil }),
              flexibleIndex < splitViewItems.count else { return }
        for index in panes.indices where index < splitViewItems.count {
            guard let wanted = panes[index].width, !splitViewItems[index].isCollapsed,
                  !collapsingIndices.contains(index) else { continue }
            let current = splitViewItems[index].viewController.view.frame.width
            if current - wanted > 1 {
                isApplyingChange = true
                applyWidth(ofPaneAt: index, width: wanted)
                isApplyingChange = false
                continue
            }
            let spare = splitViewItems[flexibleIndex].viewController.view.frame.width - panes[flexibleIndex].minWidth
            guard wanted - current > 1, spare > 1 else { continue }
            isApplyingChange = true
            applyWidth(ofPaneAt: index, width: current + min(wanted - current, spare))
            isApplyingChange = false
        }
    }

    /// Moves the divider on the flexible pane's side of this pane so it
    /// shows at its remembered width (or `width`).
    private func applyWidth(ofPaneAt index: Int, width: CGFloat? = nil) {
        guard let width = width ?? panes[index].width,
              let flexibleIndex = panes.firstIndex(where: { $0.width == nil }) else { return }
        let frame = splitViewItems[index].viewController.view.frame
        if index < flexibleIndex {
            splitView.setPosition(frame.minX + width, ofDividerAt: index)
        } else if index > 0 {
            // The last pane is measured from the split view's own edge: a
            // pane just un-collapsed may not have a real frame yet.
            let trailingEdge = index == splitViewItems.count - 1 ? splitView.bounds.maxX : frame.maxX
            splitView.setPosition(trailingEdge - width - splitView.dividerThickness, ofDividerAt: index - 1)
        }
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard didApplyInitialWidths, !isApplyingChange else { return }
        // Only a divider the user is dragging sets a width. A window resize
        // (or a pane squeezed by the window's minimum sizes) isn't a choice
        // to remember — recording it would shrink the pane for good.
        guard !splitView.inLiveResize, NSApp.currentEvent?.type == .leftMouseDragged else { return }
        for (index, item) in splitViewItems.enumerated() where index < panes.count {
            guard !item.isCollapsed, !collapsingIndices.contains(index), panes[index].width != nil else { continue }
            let width = item.viewController.view.frame.width
            guard width >= panes[index].minWidth else { continue } // mid-collapse
            // Remembered here too, not only in the layout model (which
            // doesn't re-render for a drag), so a later window resize keeps
            // this width rather than snapping back.
            panes[index].width = width
            panes[index].onWidthChange?(width)
        }
    }
}

/// An `NSSplitView` whose dividers don't draw — see
/// `PaneSplitView.transparentDividers`.
final class TransparentDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}
