import SwiftUI

struct TabBarView: View {
    var windowViewModel: WindowViewModel
    @Environment(\.openWindow) private var openWindow
    /// The strip's own width, for working out how many tabs fit.
    @State private var stripWidth: CGFloat = 0

    private static let minTabWidth: CGFloat = 110
    private static let tabSpacing: CGFloat = 4
    private static let newTabButtonWidth: CGFloat = 28
    private static let overflowButtonWidth: CGFloat = 32

    /// Tabs share the width (flexible, 110–220pt). Once they'd get
    /// narrower than that, the rest go into a » menu at the end instead of
    /// shrinking into unreadable slivers — the active tab always stays
    /// visible in the strip. (Measured with a background `GeometryReader`
    /// rather than a `ScrollView`: an earlier scrolling version never laid
    /// out reliably here.)
    var body: some View {
        let shown = shownTabs
        let hiddenCount = windowViewModel.tabs.count - shown.count
        HStack(spacing: Self.tabSpacing) {
            ForEach(shown) { tab in
                DraggableTabView(
                    tab: tab,
                    isActive: tab.id == windowViewModel.activeTabID,
                    windowViewModel: windowViewModel,
                    onSelect: { windowViewModel.selectTab(tab) },
                    onHoverSwitch: { windowViewModel.selectTab(tab) },
                    onClose: {
                        guard windowViewModel.tabs.count > 1 || CloseLastTabConfirmation.confirm() else { return }
                        windowViewModel.closeTab(tab)
                    },
                    onTearOff: { tab, screenPoint in
                        let token = TabHandoffCenter.shared.store(tab, screenPoint: screenPoint)
                        openWindow(id: OneRootApp.tabHandoffWindowID, value: token)
                    },
                    onMoveToNewWindow: { tab, windowFrame in
                        guard windowViewModel.tabs.count > 1 else { return }
                        windowViewModel.detachTab(tab)
                        let point = windowFrame.map(TabHandoffCenter.cascadePoint(from:)) ?? CGPoint(x: 200, y: 700)
                        let token = TabHandoffCenter.shared.store(tab, screenPoint: point)
                        openWindow(id: OneRootApp.tabHandoffWindowID, value: token)
                    }
                )
                .frame(minWidth: Self.minTabWidth, idealWidth: 170, maxWidth: 220, minHeight: 32, maxHeight: 32)
            }

            if hiddenCount > 0 {
                overflowMenu(hiddenCount: hiddenCount)
            }

            Button {
                windowViewModel.openNewTab(at: FileManager.default.homeDirectoryForCurrentUser)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(BarButtonStyle())
            .frame(width: Self.newTabButtonWidth)
            .help("New Tab (⌘T)")
            .accessibilityLabel("New Tab")

            Spacer(minLength: 0)
                .background(TrailingTabDropCatcher(windowViewModel: windowViewModel))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
        // Flush with the card's left edge, which is square under the tabs.
        .padding(.trailing, 4)
        .frame(height: 34, alignment: .bottom)
        // One point lower, over the card's hairline edge, so the active tab
        // runs straight into the card instead of sitting on a line.
        .offset(y: 1)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { stripWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in stripWidth = width }
            }
        )
    }

    /// The tabs that fit, in order, always including the active one.
    private var shownTabs: [Tab] {
        let tabs = windowViewModel.tabs
        guard stripWidth > 0 else { return tabs }
        let available = stripWidth - 12 - Self.newTabButtonWidth - Self.tabSpacing
        let perTab = Self.minTabWidth + Self.tabSpacing
        if CGFloat(tabs.count) * perTab <= available { return tabs }
        let capacity = max(1, Int((available - Self.overflowButtonWidth - Self.tabSpacing) / perTab))
        var shown = Array(tabs.prefix(capacity))
        if let active = windowViewModel.activeTab, !shown.contains(where: { $0 === active }) {
            shown[shown.count - 1] = active
        }
        return shown
    }

    private func overflowMenu(hiddenCount: Int) -> some View {
        Menu {
            ForEach(windowViewModel.tabs) { tab in
                Button {
                    windowViewModel.selectTab(tab)
                } label: {
                    let title = TabTitle.title(for: tab.fileListViewModel.currentLocationURL)
                    if tab.id == windowViewModel.activeTabID {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text("»\u{2009}\(hiddenCount)")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: Self.overflowButtonWidth)
        .help("\(hiddenCount) more tabs")
        .accessibilityLabel("\(hiddenCount) more tabs")
    }
}

/// The tab's rendered label/close-button content, hosted inside
/// `TabDragHostView` (see `DraggableTabView.swift`) — that outer `NSView`
/// owns click-vs-drag mouse tracking and calls `onSelect` itself, so
/// there's no tap gesture on the background here (an `NSHostingView` only
/// receives mouse events for the specific controls inside it, like the
/// close button below; everywhere else falls through to the AppKit view
/// hosting this, which is exactly what makes drag detection possible).
struct TabButtonContent: View {
    /// Observed so a split, or focus moving between a split tab's panes,
    /// retitles the tab (it shows the focused pane's folder).
    var tab: Tab
    let isActive: Bool
    let onClose: () -> Void
    /// This view is hosted in its own `NSHostingView` (see below), which
    /// doesn't inherit the window's environment — so it reads the theme
    /// itself.
    private var themeStore = ThemeStore.shared
    /// For a Workspace tab's name — kept current if it's renamed.
    private var workspaces = WorkspaceStore.shared
    @State private var isHovering = false

    var body: some View {
        let theme = themeStore.current
        let workspace = tab.workspaceID.flatMap(workspaces.workspace)
        HStack(spacing: 7) {
            TabIcon(fileListViewModel: tab.fileListViewModel, isSplit: tab.isSplit, isWorkspace: workspace != nil, isActive: isActive, theme: theme)
            TabTitle(fileListViewModel: tab.fileListViewModel, workspaceName: workspace?.name, isActive: isActive)
            // Pushes the close button to the trailing edge.
            Spacer(minLength: 2)
            // On the active tab and on hover only, so the strip stays calm;
            // ⌘W and the tab's own menu cover closing without the mouse.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isActive || isHovering ? 1 : 0)
            .allowsHitTesting(isActive || isHovering)
            .help("Close Tab (⌘W)")
            .accessibilityLabel("Close Tab")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The active tab is the same white as the card under it and joins
        // it, like a folder tab; the others sit lightly on the backdrop.
        .background { tabSurface(theme) }
        .onHover { isHovering = $0 }
        // The file-drag-hover-to-switch-tabs tint and the actual drop
        // handling both live in `TabDragHostView` (AppKit, one level up)
        // — see its doc comment for why a SwiftUI `.onDrop` here couldn't
        // coexist with reordering.
    }
}

extension TabButtonContent {
    /// The active tab is solid — the card's own color, joining the card
    /// below — with a soft lift; the others are frosted glass over the
    /// window, with a hairline edge so each one stays easy to pick out.
    /// (Under Reduce Transparency, macOS makes the frost opaque by itself.)
    @ViewBuilder
    fileprivate func tabSurface(_ theme: Theme) -> some View {
        let shape = TopRoundedRectangle(radius: 9)
        if isActive {
            shape
                .fill(theme.contentBackgroundColor)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 3, y: -1)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(theme.isDark
                    ? Color.black.opacity(isHovering ? 0.05 : 0.18)
                    : Color.white.opacity(isHovering ? 0.45 : 0.28)))
                .overlay(shape.stroke(theme.separatorColor.opacity(0.8), lineWidth: 0.5))
        }
    }
}

/// Its own view so it observes whichever pane's view model is current —
/// the folder name updates as that pane navigates.
/// A Workspace tab keeps the Workspace's name wherever it is inside it, so
/// it reads as that Workspace from any other tab; the folder is in its
/// tooltip.
struct TabTitle: View {
    var fileListViewModel: FileListViewModel
    let workspaceName: String?
    let isActive: Bool

    var body: some View {
        let folder = Self.title(for: fileListViewModel.currentLocationURL)
        Text(workspaceName ?? folder)
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(workspaceName.map { "Workspace \u{201C}\($0)\u{201D} \u{2014} \(folder)" } ?? "")
            .accessibilityLabel(workspaceName.map { "Workspace \($0), in \(folder)" } ?? folder)
    }

    static func title(for url: URL?) -> String {
        guard let url else { return "New Tab" }
        if let location = VirtualLocation(url: url) { return location.title }
        let name = url.friendlyFolderName
        return name.isEmpty || name == "/" ? "Root" : name
    }

    /// What VoiceOver calls the tab: its folder, or "Workspace X, in folder".
    @MainActor
    static func spokenTitle(for tab: Tab) -> String {
        let folder = title(for: tab.fileListViewModel.currentLocationURL)
        guard let name = tab.workspaceID.flatMap(WorkspaceStore.shared.workspace)?.name else { return folder }
        return "Workspace \(name), in \(folder)"
    }
}

/// A home icon for a home folder, otherwise a folder — or the Workspace
/// icon in a Workspace, the split icon while Dual Pane is on. In the accent color on the active tab, gray on the
/// others: that, with the active tab's solid background and bold title, is
/// what marks the current tab.
private struct TabIcon: View {
    var fileListViewModel: FileListViewModel
    let isSplit: Bool
    let isWorkspace: Bool
    let isActive: Bool
    let theme: Theme

    /// The same for every Workspace tab (not each Workspace's own icon), so
    /// they're recognizable at a glance.
    static let workspaceSymbol = "rectangle.3.group.fill"

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(isActive ? theme.accentColor : Color.secondary)
            .help(isSplit ? "Dual Pane" : "")
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if isSplit { return "rectangle.split.2x1" }
        if isWorkspace { return Self.workspaceSymbol }
        if let location = fileListViewModel.virtualLocation { return location.systemImage }
        if fileListViewModel.currentDirectory == FileManager.default.homeDirectoryForCurrentUser { return "house.fill" }
        return "folder.fill"
    }
}

/// Rounded top corners, square bottom — the tab joins the card below it.
private struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
