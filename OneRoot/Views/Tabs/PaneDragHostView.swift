import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Internal-only, like `.oneRootTab`: carries a `PaneDragRegistry` token.
    static let oneRootPane = NSPasteboard.PasteboardType("com.oneroot.pane")
}

/// In-memory handoff for a pane being dragged by its header — the
/// pasteboard can only carry a token, not the live `Tab`. Same idea as
/// `TabDragRegistry`.
@MainActor
final class PaneDragRegistry {
    static let shared = PaneDragRegistry()

    private var inFlight: [UUID: (tab: Tab, pane: Pane)] = [:]

    private init() {}

    func begin(_ tab: Tab, pane: Pane) -> UUID {
        let token = UUID()
        inFlight[token] = (tab, pane)
        return token
    }

    func lookup(_ token: UUID) -> (tab: Tab, pane: Pane)? {
        inFlight[token]
    }

    func end(_ token: UUID) {
        inFlight.removeValue(forKey: token)
    }
}

/// The header strip above each half of a split tab, made draggable: drop it
/// on the other pane's header to swap the two sides, or anywhere outside
/// the window to tear the pane off into its own window as a single-pane tab.
/// A plain click focuses the pane.
///
/// AppKit rather than SwiftUI drag and drop for the reason
/// `DraggableTabView` gives: only `NSDraggingSource` reports a drop that
/// landed *nowhere*, which is the tear-off signal.
struct PaneHeaderBar: NSViewRepresentable {
    let tab: Tab
    let pane: Pane
    let viewModel: FileListViewModel
    let isFocused: Bool
    let onTearOff: (FileListViewModel, NSPoint) -> Void

    func makeNSView(context: Context) -> PaneDragHostView {
        PaneDragHostView()
    }

    func updateNSView(_ nsView: PaneDragHostView, context: Context) {
        nsView.tab = tab
        nsView.pane = pane
        nsView.onTearOff = onTearOff
        nsView.viewModel = viewModel
        nsView.isFocused = isFocused
        nsView.refreshContent()
    }
}

@MainActor
final class PaneDragHostView: NSView, NSDraggingSource {
    var tab: Tab!
    var pane: Pane = .primary
    var viewModel: FileListViewModel!
    var isFocused = false
    var onTearOff: ((FileListViewModel, NSPoint) -> Void)?

    private var hostingView: NSHostingView<PaneHeader>?
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var currentDragToken: UUID?
    private var isDropTarget = false {
        didSet { if oldValue != isDropTarget { refreshContent() } }
    }

    private static let dragStartThreshold: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.oneRootPane])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshContent() {
        guard let viewModel else { return }
        let content = PaneHeader(viewModel: viewModel, isFocused: isFocused, isDropTarget: isDropTarget)
        if let hostingView {
            hostingView.rootView = content
            return
        }
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
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = hostingView
    }

    // MARK: Click vs. drag

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownLocation, let tab else { return }
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) > Self.dragStartThreshold else { return }
        isDragging = true

        let token = PaneDragRegistry.shared.begin(tab, pane: pane)
        currentDragToken = token
        let item = NSPasteboardItem()
        item.setString(token.uuidString, forType: .oneRootPane)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
        }
        guard !isDragging else { return }
        tab?.focus(pane)
    }

    // MARK: Accessibility

    // "Left pane, Documents, selected" — pressing it makes that pane the
    // one you're working in, like clicking its header.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityRoleDescription() -> String? { "pane" }
    override func accessibilityLabel() -> String? {
        let side = pane == .primary ? "Left pane" : "Right pane"
        return "\(side), \(TabTitle.title(for: viewModel?.currentLocationURL))"
    }
    override func accessibilityValue() -> Any? { NSNumber(value: isFocused) }
    override func isAccessibilitySelected() -> Bool { isFocused }

    override func accessibilityPerformPress() -> Bool {
        tab?.focus(pane)
        return true
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

    // MARK: Drag source

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    /// Nothing claimed the drop. Outside this window, that's a tear-off;
    /// inside it (over the file list, say) it's treated as a cancel, so a
    /// slightly-missed drop on the other header doesn't throw the pane
    /// into a new window.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { currentDragToken = nil }
        guard let token = currentDragToken else { return }
        defer { PaneDragRegistry.shared.end(token) }
        guard operation.isEmpty,
              PaneDragRegistry.shared.lookup(token) != nil,
              let window, !window.frame.contains(screenPoint),
              let tab, let onTearOff,
              let removed = tab.detach(pane) else { return }
        onTearOff(removed, screenPoint)
    }

    // MARK: Drop destination — swap with the other pane of the same tab

    /// `nil` unless this is a pane header drag from this same tab.
    private func draggedPane(_ info: NSDraggingInfo) -> Pane? {
        guard let string = info.draggingPasteboard.string(forType: .oneRootPane),
              let token = UUID(uuidString: string),
              let (draggedTab, draggedPane) = PaneDragRegistry.shared.lookup(token),
              draggedTab === tab else { return nil }
        return draggedPane
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = draggedPane(sender) else { return [] }
        isDropTarget = dragged != pane
        // Its own header accepts too (as a no-op), so dropping a pane back
        // where it started is never mistaken for a tear-off.
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedPane(sender) == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let dragged = draggedPane(sender) else { return false }
        if dragged != pane {
            tab.swapPanes()
        }
        return true
    }
}

/// What the header shows: that pane's folder, tinted when it's the focused
/// pane (the one the toolbar, address bar, and sidebar act on), and
/// highlighted while another pane's header is dragged over it.
struct PaneHeader: View {
    var viewModel: FileListViewModel
    let isFocused: Bool
    let isDropTarget: Bool
    /// Hosted in its own `NSHostingView`, which doesn't inherit the
    /// window's environment, so it reads the theme itself.
    private var themeStore = ThemeStore.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isFocused ? themeStore.current.accentColor : .secondary)
            Text(viewModel.virtualLocation?.title ?? viewModel.currentDirectory?.friendlyFolderName ?? "")
                .fontWeight(isFocused ? .semibold : .regular)
                .lineLimit(1)
            Text(viewModel.currentDirectory?.deletingLastPathComponent().path ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag onto the other pane's header to swap sides, or out of the window to open this pane in its own window")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .help(viewModel.currentDirectory?.path ?? "")
    }

    private var background: Color {
        let accent = themeStore.current.accentColor
        if isDropTarget { return accent.opacity(0.35) }
        return isFocused ? accent.opacity(0.15) : Color.clear
    }
}
