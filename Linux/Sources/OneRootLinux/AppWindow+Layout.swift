import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The pane layout: which of the sidebar, folder hierarchy and Inspector
/// show, and how wide — the shared `WindowLayoutModel`, saved per window and
/// remembered for the next one (as on the Mac).
extension AppWindow {
    func wirePanes() {
        hierarchyPane.onNavigate = { [weak self] url in self?.activePane?.navigate(to: url) }
        hierarchyPane.onOpenInNewTab = { [weak self] url in self?.newTab(at: url) }
        hierarchyPane.onCopyPath = { [weak self] url in
            self?.activePane?.copyPaths([url])
            self?.showToast("Copied the path")
        }
        hierarchyPane.onDrop = { [weak self] urls, folder, move in
            self?.activePane?.handleDrop(urls: urls, into: folder, move: move)
        }
        sidebar.onDropFiles = { [weak self] urls, folder, move in
            self?.activePane?.handleDrop(urls: urls, into: folder, move: move)
        }
        sidebar.onTrashFiles = { [weak self] urls in
            self?.activePane?.moveToTrash(urls: urls)
        }
        inspector.onAction = { [weak self] name in self?.fileActions[name]?.activate() }
    }

    func wireLayout() {
        layoutWatch = ObservationWatch.watch({ [viewModel] in viewModel.layout.layout }) { [weak self] _ in
            self?.applyFitted()
        }
        // A window narrower than its panes needs hides the Inspector, then
        // the hierarchy, then the sidebar (`WindowLayout.fitted`); widening it
        // brings them back. The chosen layout is never changed by this.
        window.onNotify(.custom("default-width")) { [weak self] in self?.applyFitted() }
        watchWidth()
        let model = viewModel.layout
        outerPaned.onNotify(.custom("position")) { [weak self] in
            guard let self, !self.isApplyingLayout, self.sidebar.widget.visible else { return }
            model.recordSize(\.destinationsWidth, Double(self.outerPaned.position))
        }
        hierarchyPaned.onNotify(.custom("position")) { [weak self] in
            guard let self, !self.isApplyingLayout, self.hierarchyPane.widget.visible else { return }
            model.recordSize(\.hierarchyWidth, Double(self.hierarchyPaned.position))
        }
        inspectorPaned.onNotify(.custom("position")) { [weak self] in
            guard let self, !self.isApplyingLayout, self.inspector.widget.visible else { return }
            let width = self.inspectorPaned.width
            guard width > 0 else { return }
            model.recordSize(\.inspectorWidth, Double(width - self.inspectorPaned.position))
        }
    }

    /// `default-width` isn't notified when a window manager (or the user)
    /// resizes the window, so the width is also checked once per frame; the
    /// check is a single integer compare unless the width changed.
    private func watchWidth() {
        final class Ref { weak var window: AppWindow?; var width = 0 }
        let ref = Ref()
        ref.window = self
        gtk_widget_add_tick_callback(window.widgetPointer, { _, _, data in
            guard let data else { return gboolean(0) }
            let ref = Unmanaged<Ref>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard let window = ref.window else { return }
                let width = window.window.width
                guard width > 0, width != ref.width else { return }
                ref.width = width
                window.applyFitted()
            }
            return ref.window == nil ? gboolean(0) : gboolean(1)
        }, Unmanaged.passRetained(ref).toOpaque(), { data in
            if let data { Unmanaged<Ref>.fromOpaque(data).release() }
        })
    }

    /// The saved layout, narrowed to what fits the window's current width.
    func applyFitted() {
        let layout = viewModel.layout.layout
        let width = Double(window.width > 0 ? window.width : Int(window.defaultWidth))
        var fitted = layout.fitted(to: width)
        // `fitted` budgets each pane's minimum width; the panes are actually
        // drawn at their saved widths, so also keep the file list usable then.
        func listWidth() -> Double {
            width - (fitted.showsDestinations ? fitted.destinationsWidth : 0)
                - (fitted.showsHierarchy ? fitted.hierarchyWidth : 0)
                - (fitted.showsInspector ? fitted.inspectorWidth : 0)
        }
        if listWidth() < WindowLayout.minimumListWidth { fitted.showsInspector = false }
        if listWidth() < WindowLayout.minimumListWidth { fitted.showsHierarchy = false }
        if listWidth() < WindowLayout.minimumListWidth { fitted.showsDestinations = false }
        guard fitted != lastAppliedLayout else { return }
        lastAppliedLayout = fitted
        apply(fitted)
    }

    private func apply(_ layout: WindowLayout) {
        isApplyingLayout = true
        sidebar.widget.visible = layout.showsDestinations
        hierarchyPane.widget.visible = layout.showsHierarchy
        inspector.widget.visible = layout.showsInspector
        sidebarToggle?.active = layout.showsDestinations
        hierarchyButton.active = layout.showsHierarchy
        inspectorButton.active = layout.showsInspector
        outerPaned.position = Int(layout.destinationsWidth)
        hierarchyPaned.position = Int(layout.hierarchyWidth)

        if layout.showsInspector {
            if let pane = activePane { inspector.bind(to: pane) }
        } else {
            inspector.unbind()
        }
        isApplyingLayout = false

        // The Inspector keeps its width as the window resizes, so its divider
        // is placed from the right edge once the window has a size.
        let inspectorWidth = Int(layout.inspectorWidth)
        MainContext.task { [weak self] in
            guard let self, self.inspector.widget.visible else { return }
            // The paned's own width is stale while other panes were just
            // shown or hidden (it is measured before the next layout pass),
            // so work it out from the window.
            let windowWidth = self.window.width > 0 ? self.window.width : Int(self.window.defaultWidth)
            let width = windowWidth
                - (layout.showsDestinations ? Int(layout.destinationsWidth) : 0)
                - (layout.showsHierarchy ? Int(layout.hierarchyWidth) : 0)
            self.isApplyingLayout = true
            self.inspectorPaned.position = max(0, width - inspectorWidth)
            self.isApplyingLayout = false
        }
    }
}
