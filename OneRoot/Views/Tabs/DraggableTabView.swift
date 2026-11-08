import AppKit
import SwiftUI

/// Bridges a single tab's SwiftUI content to a real `NSView` so it can act
/// as both an `NSDraggingSource` (drag to reorder, or drag past *any*
/// OneRoot tab bar to tear off into a new window — Safari/Chrome tab
/// behavior) and a drop destination (reordering, and accepting a tab
/// dragged in from another window's tab bar).
///
/// This can't be done in pure SwiftUI: `.onDrag`/`.dropDestination` have
/// no way to report a drag that ended over *no* valid destination at all
/// (empty desktop, another app) versus one of our own tab bars — exactly
/// the signal a tear-off needs. AppKit's `NSDraggingSource` gives that
/// directly via the `operation` passed to
/// `draggingSession(_:endedAt:operation:)`: empty means nothing in this
/// app claimed the drop.
struct DraggableTabView: NSViewRepresentable {
    let tab: Tab
    let isActive: Bool
    let windowViewModel: WindowViewModel
    let onSelect: () -> Void
    let onHoverSwitch: () -> Void
    let onClose: () -> Void
    let onTearOff: (Tab, NSPoint) -> Void
    /// The tab menu's Move Tab to New Window, with this window's frame.
    let onMoveToNewWindow: (Tab, CGRect?) -> Void

    func makeNSView(context: Context) -> TabDragHostView {
        let view = TabDragHostView()
        view.windowViewModel = windowViewModel
        return view
    }

    func updateNSView(_ nsView: TabDragHostView, context: Context) {
        nsView.tab = tab
        nsView.isActive = isActive
        nsView.windowViewModel = windowViewModel
        nsView.onSelect = onSelect
        nsView.onHoverSwitch = onHoverSwitch
        nsView.onTearOff = onTearOff
        nsView.onClose = onClose
        nsView.onMoveToNewWindow = onMoveToNewWindow
        nsView.setContent(TabButtonContent(tab: tab, isActive: isActive, onClose: onClose))
    }
}

/// Owns the actual mouse tracking: a plain click (mouse down/up with
/// negligible movement) selects the tab; movement past a small threshold
/// starts a real AppKit dragging session instead. The close button lives
/// entirely inside the hosted SwiftUI content and keeps working
/// unmodified — `NSHostingView` hit-tests into it directly for clicks
/// that land there, so this view's own `mouseDown` never sees them.
///
/// Also owns the "drag a *file* onto a background tab switches to it"
/// destination handling (`.fileURL`), which used to live as a SwiftUI
/// `.onDrop` inside the hosted content. It has to live here instead: when
/// AppKit resolves which view a drag belongs to, it walks up from the
/// hit-tested view looking for the nearest one registered for *any* drag
/// type and stops at the first match — even if that view's own registered
/// types don't include the one actually being dragged. With the file-drop
/// registration on the *inner* hosted view, it was winning that search and
/// silently rejecting every `.oneRootTab` drag before this view ever saw
/// it, which broke reordering (tear-off still "worked" only because
/// dropping outside the tab bar entirely has no competing view at all).
/// Registering both types on this one view removes the competition.
@MainActor
final class TabDragHostView: NSView, NSDraggingSource {
    var tab: Tab!
    var isActive = false
    weak var windowViewModel: WindowViewModel!
    var onSelect: (() -> Void)?
    var onHoverSwitch: (() -> Void)?
    var onTearOff: ((Tab, NSPoint) -> Void)?
    var onClose: (() -> Void)?
    var onMoveToNewWindow: ((Tab, CGRect?) -> Void)?

    private var hostingView: NSHostingView<TabButtonContent>?
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var currentDragToken: UUID?
    private var fileHoverWorkItem: DispatchWorkItem?

    private static let dragStartThreshold: CGFloat = 4
    private static let fileHoverSwitchDelay: TimeInterval = 0.6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.oneRootTab, .fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: TabButtonContent) {
        guard let hostingView else {
            let hostingView = NSHostingView(rootView: content)
            // Sized by the SwiftUI frame this view sits in — never the other way
            // round. Left at its default, the hosting view pushes its content's
            // size back out as constraints, which fed the tab strip's own width
            // measurement into an endless layout loop that crashed the app.
            hostingView.sizingOptions = []
            // Nor keep clear of the window's hidden title bar, which the tab strip
            // sits under — that pushed the tab's content halfway out of view.
            hostingView.safeAreaRegions = []
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.hostingView = hostingView
            return
        }
        hostingView.rootView = content
    }

    // MARK: Click vs. drag

    /// The tab strip is in the window's title bar area, and macOS decides
    /// ahead of any press that a drag there moves the window — the window
    /// moved and the tab shook in place, except on the few points of a tab
    /// below the title bar. `mouseDownCanMoveWindow`, being a control, and
    /// making the window unmovable as the press arrives all came too late.
    /// So the window is unmovable for as long as the pointer is over a tab,
    /// and movable again once it leaves; the rest of the strip still drags
    /// the window. If this ever stops working, #84 has the fallback.
    private weak var heldWindow: NSWindow?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard let window, heldWindow == nil, window.isMovable else { return }
        window.isMovable = false
        heldWindow = window
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        releaseWindow()
    }

    private func releaseWindow() {
        heldWindow?.isMovable = true
        heldWindow = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { releaseWindow() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownLocation else { return }
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) > Self.dragStartThreshold else { return }
        isDragging = true
        beginTabDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
        }
        guard !isDragging else { return }
        onSelect?()
    }

    // MARK: Tab menu

    /// Right-click (or Control-click, or VoiceOver's VO-Shift-M): the
    /// tab's own menu. The same closing commands are in the View menu
    /// for the active tab, with their shortcuts.
    override func menu(for event: NSEvent) -> NSMenu? {
        makeTabMenu()
    }

    private enum MenuCommand: Int {
        case close, closeOthers, closeToTheRight, duplicate, moveToNewWindow, newTab
    }

    private func makeTabMenu() -> NSMenu? {
        guard let tab, let windowViewModel else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasOthers = windowViewModel.tabs.count > 1
        menu.addItem(menuItem("Close Tab", .close, enabled: true))
        menu.addItem(menuItem("Close Other Tabs", .closeOthers, enabled: hasOthers))
        menu.addItem(menuItem("Close Tabs to the Right", .closeToTheRight, enabled: windowViewModel.hasTabs(after: tab)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Duplicate Tab", .duplicate, enabled: true))
        menu.addItem(menuItem("Move Tab to New Window", .moveToNewWindow, enabled: hasOthers))
        menu.addItem(.separator())
        menu.addItem(menuItem("New Tab", .newTab, enabled: true))
        return menu
    }

    /// Targets this view itself, with the command as the tag: a separate
    /// little target object's `@objc` method came through as an unknown
    /// selector, so every item silently did nothing.
    private func menuItem(_ title: String, _ command: MenuCommand, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performMenuCommand(_:)), keyEquivalent: "")
        item.target = self
        item.tag = command.rawValue
        item.isEnabled = enabled
        return item
    }

    @objc private func performMenuCommand(_ sender: NSMenuItem) {
        guard let tab, let windowViewModel, let command = MenuCommand(rawValue: sender.tag) else { return }
        switch command {
        case .close:
            onClose?()
        case .closeOthers:
            windowViewModel.closeOtherTabs(keeping: tab)
        case .closeToTheRight:
            windowViewModel.closeTabsToTheRight(of: tab)
        case .duplicate:
            windowViewModel.selectTab(tab)
            windowViewModel.duplicateActiveTab()
        case .moveToNewWindow:
            onMoveToNewWindow?(tab, window?.frame)
        case .newTab:
            windowViewModel.openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    // MARK: Accessibility

    // A tab, to VoiceOver: "Documents, selected, tab" — pressing it selects
    // it, and its menu (VO-Shift-M) and actions close it or the others.
    // Before, a tab was a bare text and an unnamed "Close" button, with no
    // way to tell which was active or to switch to one.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityRoleDescription() -> String? { "tab" }
    override func accessibilityLabel() -> String? { tab.map(TabTitle.spokenTitle(for:)) }
    override func accessibilityValue() -> Any? { NSNumber(value: isActive) }
    override func isAccessibilitySelected() -> Bool { isActive }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = makeTabMenu() else { return false }
        // On the next pass: `popUp` runs the menu modally, which would hold
        // the accessibility request open until the menu closed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: self.bounds.midX, y: self.bounds.minY), in: self)
        }
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let tab, let windowViewModel else { return nil }
        var actions = [NSAccessibilityCustomAction(name: "Close Tab") { [weak self] in
            self?.onClose?()
            return true
        }]
        if windowViewModel.tabs.count > 1 {
            actions.append(NSAccessibilityCustomAction(name: "Close Other Tabs") { [weak windowViewModel] in
                windowViewModel?.closeOtherTabs(keeping: tab)
                return true
            })
        }
        if windowViewModel.hasTabs(after: tab) {
            actions.append(NSAccessibilityCustomAction(name: "Close Tabs to the Right") { [weak windowViewModel] in
                windowViewModel?.closeTabsToTheRight(of: tab)
                return true
            })
        }
        return actions
    }

    // MARK: Drag source


    private func beginTabDrag(with event: NSEvent) {
        guard let tab, let windowViewModel else { return }
        let token = TabDragRegistry.shared.begin(tab, from: windowViewModel)
        currentDragToken = token

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(token.uuidString, forType: .oneRootTab)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard bounds.width > 0, bounds.height > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        cacheDisplay(in: bounds, to: rep)
        image.addRepresentation(rep)
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    /// An empty `operation` means the drop landed nowhere any OneRoot tab
    /// bar claimed it — empty desktop, another app, or just open space —
    /// exactly the tear-off gesture. If some tab bar's `performDragOperation`
    /// already consumed the token (a reorder or a same-app merge), the
    /// registry lookup below comes back empty and this is a no-op.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { currentDragToken = nil }
        guard operation.isEmpty,
              let token = currentDragToken,
              TabDragRegistry.shared.lookup(token) != nil,
              let tab, let windowViewModel, let onTearOff
        else { return }
        TabDragRegistry.shared.end(token)
        windowViewModel.detachTab(tab)
        onTearOff(tab, screenPoint)
    }

    // MARK: Drop destination (reorder within this bar, accept a tab dragged in from another window,
    // or — for a plain file drag, not a tab — switch to this tab after a short hover, the same way
    // Safari does, so the drop can land in *this* tab's file list once it's frontmost)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        if types.contains(.oneRootTab) { return .move }
        if types.contains(.fileURL) {
            setFileHoverTint(true)
            if !isActive {
                let workItem = DispatchWorkItem { [weak self] in self?.onHoverSwitch?() }
                fileHoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.fileHoverSwitchDelay, execute: workItem)
            }
        }
        // Rejected either way: a `.oneRootTab` drag that reaches here without
        // that type present isn't ours, and a `.fileURL` drag has nothing to
        // actually land on — just the tab label, per `onHoverSwitch` above.
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(.oneRootTab) == true ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        fileHoverWorkItem?.cancel()
        fileHoverWorkItem = nil
        setFileHoverTint(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        fileHoverWorkItem?.cancel()
        fileHoverWorkItem = nil
        setFileHoverTint(false)
    }

    private func setFileHoverTint(_ isTargeted: Bool) {
        layer?.backgroundColor = isTargeted ? NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor : nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let windowViewModel, let tab,
              let currentIndex = windowViewModel.tabs.firstIndex(where: { $0.id == tab.id }) else { return false }
        let dropX = convert(sender.draggingLocation, from: nil).x
        let destinationIndex = dropX < bounds.width / 2 ? currentIndex : currentIndex + 1
        return TabDragRegistry.shared.handleDrop(sender, into: windowViewModel, at: destinationIndex)
    }
}

/// Catches drops in the tab bar's trailing empty space (past the last
/// tab, before the "+" button) so moving a tab to the very end of the
/// strip — or into a window via its otherwise-empty tab bar — doesn't
/// require landing precisely on another tab.
struct TrailingTabDropCatcher: NSViewRepresentable {
    let windowViewModel: WindowViewModel

    func makeNSView(context: Context) -> TrailingTabDropView {
        let view = TrailingTabDropView()
        view.windowViewModel = windowViewModel
        return view
    }

    func updateNSView(_ nsView: TrailingTabDropView, context: Context) {
        nsView.windowViewModel = windowViewModel
    }
}

@MainActor
final class TrailingTabDropView: NSView {
    weak var windowViewModel: WindowViewModel!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.oneRootTab])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(.oneRootTab) == true ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let windowViewModel else { return false }
        return TabDragRegistry.shared.handleDrop(sender, into: windowViewModel, at: windowViewModel.tabs.count)
    }

    // The tab strip sits where a title bar would be (the window has none of
    // its own), so its empty space behaves like one: drag to move the
    // window, double-click to zoom or minimize per System Settings.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            if action == "Minimize" { window.performMiniaturize(nil) } else if action != "None" { window.performZoom(nil) }
            return
        }
        window.performDrag(with: event)
    }
}

