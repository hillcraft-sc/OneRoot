import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The global destination sidebar: Home, pinned folders, cloud storage,
/// volumes and shares, and the Trash. Shallow on purpose — choosing a
/// destination roots the folder hierarchy pane there and takes the active
/// tab to it; browsing deeper happens in the hierarchy, not here.
///
/// The highlighted row follows the active tab's hierarchy root, so it
/// always says where you are rather than what was last clicked. Drawn as
/// custom rows on the window backdrop (the OneRoot look) rather than a
/// system `List`, whose solid accent selection can't be restyled.
struct DestinationsSidebarView: View {
    var destinations: DestinationsViewModel
    var activeTab: Tab
    /// The active tab's focused pane — Recents/Shared show as selected
    /// while it shows them.
    var activePane: FileListViewModel
    let hierarchy: FolderHierarchyViewModel
    var onSelect: (Destination, _ inNewTab: Bool) -> Void
    var onOpenWorkspace: (Workspace, _ inNewTab: Bool) -> Void
    var onConnectToServer: () -> Void
    private var workspaces = WorkspaceStore.shared

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool
    /// Set once the arrow keys are used here, so the focus ring shows for
    /// keyboard navigation but not merely because the sidebar happens to
    /// hold focus (it usually does when a window opens).
    @State private var isNavigatingByKeyboard = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(destinations.sections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            if !section.title.isEmpty {
                                Text(section.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 2)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(section.destinations) { destination in
                                row(destination)
                            }
                        }
                    }
                    WorkspacesSidebarSection(store: workspaces, activeTab: activeTab, onOpen: onOpenWorkspace)
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            // Arrow keys move between destinations once the sidebar has
            // keyboard focus (Tab into it), like any sidebar.
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                isNavigatingByKeyboard = true
                move(direction)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { isNavigatingByKeyboard = false }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Destinations")

            StorageFooter(onConnectToServer: onConnectToServer)
        }
    }

    /// `nil` while the tab is in a Workspace — then that's what's selected.
    private var activeRootDestinationURL: URL? {
        guard activeTab.workspaceID == nil, let root = activeTab.hierarchyRoot else { return nil }
        return destinations.allDestinations.first { HierarchyRootResolver.sameLocation($0.url, root.url) }?.url
    }

    private func row(_ destination: Destination) -> some View {
        // Recents/Shared are selected while shown; a folder destination
        // while it roots the tab's hierarchy and no list is shown instead.
        let shown = activePane.virtualLocation
        let isSelected = destination.kind.isVirtual
            ? shown?.url == destination.url
            : shown == nil && destination.url == activeRootDestinationURL
        return DestinationRow(
            destination: destination,
            isSelected: isSelected,
            showsFocus: isSelected && isFocused && isNavigatingByKeyboard,
            onChoose: { choose(destination) },
            onEject: { destinations.eject(destination) },
            onDrop: { urls, move in drop(urls, on: destination, move: move) }
        )
        .contextMenu { contextMenu(for: destination) }
    }

    private func choose(_ destination: Destination) {
        guard destination.url != activeRootDestinationURL || activePane.virtualLocation != nil else { return }
        guard destination.url != activePane.virtualLocation?.url else { return }
        onSelect(destination, false)
    }

    private func move(_ direction: MoveCommandDirection) {
        let all = destinations.allDestinations
        guard !all.isEmpty else { return }
        let current = all.firstIndex { $0.url == activeRootDestinationURL }
        let next: Int
        switch direction {
        case .up: next = max((current ?? all.count) - 1, 0)
        case .down: next = min((current ?? -1) + 1, all.count - 1)
        default: return
        }
        choose(all[next])
    }

    @ViewBuilder
    private func contextMenu(for destination: Destination) -> some View {
        Button("Open in New Tab") { onSelect(destination, true) }
        // Recents and Shared aren't folders: no path, Finder, or Terminal.
        if !destination.kind.isVirtual {
            folderMenuItems(for: destination)
        }
    }

    @ViewBuilder
    private func folderMenuItems(for destination: Destination) -> some View {
        Divider()
        if destination.kind == .pinned {
            Button("Remove from Sidebar") { destinations.unpin(destination) }
        }
        if destination.isEjectable {
            Button(destination.kind == .networkVolume ? "Disconnect" : "Eject") { destinations.eject(destination) }
        }
        if destination.kind == .trash {
            Button("Empty Trash…") { emptyTrash(destination) }
        }
        if destination.kind == .pinned || destination.isEjectable || destination.kind == .trash {
            Divider()
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(destination.url.path, forType: .string)
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([destination.url]) }
        if destination.kind != .trash {
            Button("Open in Terminal") { openInTerminal(destination.url) }
        }
    }

    /// Same rules as the tree and file list: no folder into itself; ⌥ copies,
    /// otherwise it moves. Onto the Trash it's a real Move to Trash, so it
    /// can be restored and undone.
    private func drop(_ urls: [URL], on destination: Destination, move: Bool) {
        guard !destination.kind.isVirtual else { return }
        if destination.kind == .trash {
            guard TrashConfirmation.confirm(urls.map(\.lastPathComponent)) else { return }
            hierarchy.moveToTrash(urls)
            return
        }
        guard isValidDropTarget(destination.url, for: urls) else { return }
        let node = FileNode(url: destination.url, name: destination.name, isDirectory: true, size: nil, modificationDate: nil, kind: nil)
        hierarchy.handleDrop(urls: urls, into: node, move: move)
    }

    private func emptyTrash(_ destination: Destination) {
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "This will permanently erase the items in the Trash. This can't be undone."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let node = FileNode(url: destination.url, name: destination.name, isDirectory: true, size: nil, modificationDate: nil, kind: nil)
        hierarchy.emptyTrash(node)
    }
}

/// One destination: icon and name in a rounded row, a soft pill when it's
/// the active tab's root, and an eject button for drives and shares.
private struct DestinationRow: View {
    let destination: Destination
    let isSelected: Bool
    let showsFocus: Bool
    var onChoose: () -> Void
    var onEject: () -> Void
    var onDrop: ([URL], _ move: Bool) -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: destination.kind.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(destination.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if destination.isEjectable {
                Button(action: onEject) {
                    Image(systemName: "eject")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(destination.kind == .networkVolume ? "Disconnect" : "Eject")
                .accessibilityLabel(destination.kind == .networkVolume ? "Disconnect \(destination.name)" : "Eject \(destination.name)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.accentColor, lineWidth: isDropTarget ? 2 : (showsFocus ? 1 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onChoose)
        .onHover { isHovering = $0 }
        .help(destination.url.path)
        .onDrop(of: [.fileURL], delegate: DestinationDropDelegate(isTargeted: $isDropTarget, onDrop: onDrop))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onChoose() }
    }

    /// A soft neutral pill, as in the design — the accent stays for the
    /// icon, so the selection reads without a block of color.
    private var background: Color {
        if isSelected { return Color.primary.opacity(theme.isDark ? 0.12 : 0.08) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    /// Dark outline icons, like the design's; the accent marks the current
    /// destination and the cloud services.
    private var iconColor: Color {
        if isSelected { return theme.accentColor }
        switch destination.kind {
        case .cloud: return theme.accentColor
        default: return Color.primary.opacity(0.7)
        }
    }
}

/// The bottom of the sidebar: how full the startup disk is, Connect to
/// Server, and Settings.
private struct StorageFooter: View {
    var onConnectToServer: () -> Void

    @State private var space: VolumeSpace?
    @State private var volumeName = "Macintosh HD"
    @Environment(\.appTheme) private var theme

    /// Blue (the accent) while there's room, orange from 80% used, red
    /// from 90% (#59).
    private func barColor(_ level: VolumeSpace.Level) -> Color {
        switch level {
        case .normal: return theme.accentColor
        case .nearlyFull: return .orange
        case .full: return .red
        }
    }

    /// "254 GB", "1.2 TB" — whole gigabytes, as a disk gauge reads, so it
    /// fits the sidebar ("253.96 GB of 494.35 GB" didn't).
    static func compact(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 {
            let terabytes = (gigabytes / 100).rounded() / 10
            return terabytes == terabytes.rounded() ? "\(Int(terabytes)) TB" : "\(terabytes) TB"
        }
        return "\(Int(gigabytes.rounded())) GB"
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(volumeName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let space {
                        let used = space.totalCapacity - space.availableCapacity
                        Text("\(Self.compact(used)) of \(Self.compact(space.totalCapacity)) used")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 2)
                Menu {
                    Button("Connect to Server…", action: onConnectToServer)
                    SettingsLink { Text("Settings…") }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(.secondary)
                .fixedSize()
                .help("Connect to Server, Settings")
                .accessibilityLabel("More")
            }
            if let space {
                ProgressView(value: Double(space.totalCapacity - space.availableCapacity), total: Double(max(space.totalCapacity, 1)))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .tint(barColor(space.level))
                    .accessibilityLabel("\(volumeName) storage used")
                    .accessibilityValue(
                        ["\(Int((space.usedFraction * 100).rounded())) percent", space.level.description].compactMap { $0 }.joined(separator: ", ")
                    )
                    .help(space.level.description.map { "\(volumeName) is \($0)" } ?? "")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(theme.isDark ? 0.06 : 0.04))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .task {
            let root = URL(fileURLWithPath: "/")
            space = await VolumeSpaceService().space(for: root)
            if let name = await VolumeSpaceService().volumeName(for: root) { volumeName = name }
        }
    }
}

/// ⌥ held = copy, otherwise move — matching the breadcrumb bar's drop
/// targets, the folder tree, and the file list.
struct DestinationDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: ([URL], _ move: Bool) -> Void

    private var isCopy: Bool { NSEvent.modifierFlags.contains(.option) }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isCopy ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let move = !isCopy
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            onDrop(urls, move)
        }
        return true
    }
}

extension DestinationKind {
    /// Restrained, native SF Symbols — color is left to the sidebar's
    /// own (accent) styling, never warning colors for ordinary places.
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .applications: return "square.grid.2x2"
        case .bootVolume: return "internaldrive"
        case .volume: return "externaldrive"
        case .networkVolume: return "server.rack"
        case .cloud: return "icloud"
        case .pinned: return "pin"
        case .trash: return "trash"
        case .folder: return "folder"
        case .recents: return VirtualLocation.recents.systemImage
        case .shared: return VirtualLocation.shared.systemImage
        }
    }
}
