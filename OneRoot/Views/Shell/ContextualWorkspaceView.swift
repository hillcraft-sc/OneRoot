import SwiftUI

/// The tool cards along the bottom of the window — File Operations and
/// Visualize. Shown or hidden as a row (⌃⌘B, or
/// the toggle at the top right); hiding it never stops anything running.
/// Drag its top edge to change its height.
struct ToolCardsView: View {
    var tab: Tab
    var layout: WindowLayoutModel
    let windowViewModel: WindowViewModel

    private var operations = FileOperationProgressCenter.shared
    @State private var visualize = VisualizeViewModel()
    /// The height while its handle is being dragged; stored on release.
    @State private var dragHeight: Double?
    @State private var heightAtDragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            HStack(spacing: 10) {
                // Wide enough for its header (title, the three-way picker,
                // Clear, help) — narrower, the header spilled out over the
                // gap to the next card.
                FileOperationsCard(center: operations)
                    .frame(minWidth: 480, idealWidth: 500, maxWidth: 540)
                VisualizeFolderCard(tab: tab, viewModel: visualize)
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
            .frame(height: dragHeight ?? layout.layout.workspaceHeight)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = heightAtDragStart ?? layout.layout.workspaceHeight
                        heightAtDragStart = start
                        // Dragging up makes the cards taller.
                        dragHeight = (start - value.translation.height).clamped(to: WindowLayout.workspaceHeightRange)
                    }
                    .onEnded { _ in
                        if let dragHeight { layout.recordSize(\.workspaceHeight, dragHeight) }
                        heightAtDragStart = nil
                        dragHeight = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

/// Visualize for the focused pane's folder: follows it as you browse,
/// opens folders and selects files in that pane.
private struct VisualizeFolderCard: View {
    var tab: Tab
    var viewModel: VisualizeViewModel

    var body: some View {
        PaneVisualize(pane: tab.fileListViewModel, viewModel: viewModel)
    }
}

/// Observes the pane itself, so its folder changes reach the card.
private struct PaneVisualize: View {
    var pane: FileListViewModel
    var viewModel: VisualizeViewModel

    var body: some View {
        VisualizeCard(
            viewModel: viewModel,
            folder: pane.currentDirectory,
            onOpenFolder: { pane.navigate(to: $0) },
            onReveal: { pane.reveal($0) }
        )
    }
}

/// A tool card's frame: an accent-tinted symbol and title, an optional
/// trailing control, then the content.
private struct ToolCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                accessory
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Copies, moves, compressions, and extractions in progress — the same
/// numbers their floating progress windows show, with Cancel. Byte counts
/// only where the operation really reports them. Below them, the ones that
/// finished this session: done, cancelled, or failed with the details and,
/// for a copy or move, Retry for what didn't finish.
private struct FileOperationsCard: View {
    var center: FileOperationProgressCenter
    /// Failures whose details are expanded.
    @State private var expanded: Set<UUID> = []
    @State private var filter: Filter = .active

    /// The card's tabs, as in the design: what's running, what finished
    /// (done or cancelled), and what failed.
    enum Filter: Hashable {
        case active, completed, errors
    }

    private var completed: [FileOperationRecord] { center.recent.filter { !$0.outcome.isFailure } }
    private var errors: [FileOperationRecord] { center.recent.filter(\.outcome.isFailure) }

    var body: some View {
        ToolCard(title: "File Operations", systemImage: "arrow.left.arrow.right") {
            HStack(spacing: 10) {
                Picker("Show", selection: $filter) {
                    // Counts only when there's something to count — keeps
                    // the header inside the card.
                    Text(Self.label("Active", center.operations.count)).tag(Filter.active)
                    Text(Self.label("Completed", completed.count)).tag(Filter.completed)
                    Text(Self.label("Errors", errors.count)).tag(Filter.errors)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                if filter != .active, !(filter == .errors ? errors : completed).isEmpty {
                    Button("Clear") { center.clearRecent(failures: filter == .errors) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(filter == .errors ? "Clear the failed operations" : "Clear the finished operations")
                }
                HelpButton(topic: .fileOperationsCenter, compact: true)
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch filter {
                    case .active:
                        if center.operations.isEmpty {
                            placeholder("Nothing copying or moving right now.")
                        }
                        ForEach(center.operations) { operation in
                            row(operation)
                        }
                    case .completed:
                        if completed.isEmpty {
                            placeholder("Finished and cancelled operations show up here.")
                        }
                        ForEach(completed) { record in
                            recentRow(record)
                        }
                    case .errors:
                        if errors.isEmpty {
                            placeholder("No failed operations.")
                        }
                        ForEach(errors) { record in
                            recentRow(record)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Opened from the status line's "N failed": go straight to them.
        // Otherwise whatever's running, or else what last finished.
        .onAppear {
            if center.unseenFailureCount > 0 {
                filter = .errors
            } else if center.operations.isEmpty, !center.recent.isEmpty {
                filter = center.recent[0].outcome.isFailure ? .errors : .completed
            }
        }
    }

    private static func label(_ title: String, _ count: Int) -> String {
        count == 0 ? title : "\(title) (\(count))"
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }

    private func row(_ operation: FileOperationProgress) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: operation.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(operation.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if operation.isIndeterminate, !operation.isPaused {
                    ProgressView().progressViewStyle(.linear)
                } else {
                    // Gray and still while paused.
                    ProgressView(value: Double(operation.completedBytes), total: Double(max(operation.totalBytes, 1)))
                        .tint(operation.isPaused ? .secondary : nil)
                }
                TimelineView(.periodic(from: operation.startDate, by: 1)) { context in
                    HStack(spacing: 12) {
                        Text(FileOperationText.status(for: operation, now: context.date))
                        if let item = FileOperationText.currentItem(for: operation) {
                            Text(item)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                routeText(source: operation.sourceFolder, destination: operation.destinationFolder)
            }
            PauseOperationButton(operation: operation)
            CancelOperationButton(operation: operation)
        }
    }

    @ViewBuilder
    private func routeText(source: URL?, destination: URL?) -> some View {
        if let route = FileOperationText.route(source: source, destination: destination) {
            Text(route)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(route)
        }
    }

    private func recentRow(_ record: FileOperationRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            outcomeIcon(record.outcome)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(FileOperationText.summary(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message, let detail) = record.outcome {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        DisclosureGroup(isExpanded: isExpanded(record.id)) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text("Details")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                routeText(source: record.sourceFolder, destination: record.destinationFolder)
            }
            Spacer(minLength: 4)
            if let destination = record.destinationFolder {
                Button("Show") {
                    NotificationCenter.default.post(
                        name: .revealInOneRoot,
                        object: RevealInOneRootRequest(url: destination, openInNewTab: true)
                    )
                }
                .controlSize(.small)
                .help("Open \(FileOperationText.shortPath(destination)) in a new tab")
                .accessibilityLabel("Show where \(record.title) went")
            }
            if record.retry != nil {
                Button("Retry") { center.retry(record.id) }
                    .controlSize(.small)
                    .help("Try again with the items that didn't finish")
                    .accessibilityLabel("Retry \(record.title)")
            }
            Button {
                center.removeRecord(record.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Remove from the list")
            .accessibilityLabel("Remove \(record.title) from the list")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func outcomeIcon(_ outcome: FileOperationOutcome) -> some View {
        switch outcome {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Done")
        case .cancelled:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cancelled")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Failed")
        }
    }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

}

/// The file-list card's bottom line: item counts (or an error/archive
/// status), the running-operations summary, the icon-size slider in Grid,
/// and free space on the current volume.
struct CardStatusBar: View {
    var viewModel: FileListViewModel
    var layout: WindowLayoutModel
    let windowViewModel: WindowViewModel

    private var operations = FileOperationProgressCenter.shared
    @State private var volumeSpace: VolumeSpace?
    @AppStorage(FileViewMode.iconSizeKey) private var iconSize = FileViewMode.defaultIconSize

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private let volumeSpaceService = VolumeSpaceService()

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.archiveOperationStatus != nil {
                ProgressView()
                    .controlSize(.small)
            }
            Text(statusText)
                .lineLimit(1)
            if !operations.operations.isEmpty {
                Button {
                    windowViewModel.setWorkspaceExpanded(true)
                } label: {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(operations.operations.count == 1 ? "1 operation" : "\(operations.operations.count) operations")
                    }
                }
                .buttonStyle(.borderless)
                .help("Show File Operations")
            }
            if operations.unseenFailureCount > 0 {
                Button {
                    windowViewModel.setWorkspaceExpanded(true)
                } label: {
                    Label(operations.unseenFailureCount == 1 ? "1 failed" : "\(operations.unseenFailureCount) failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Show what went wrong in File Operations")
            }
            Spacer()
            if viewModel.viewMode == .icons {
                // Finder keeps its icon-size slider in the status bar too.
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3").imageScale(.small)
                        .accessibilityHidden(true)
                    Slider(value: $iconSize, in: FileViewMode.iconSizeRange)
                        .controlSize(.mini)
                        .frame(width: 110)
                        .accessibilityLabel("Icon size")
                        .accessibilityValue("\(Int(iconSize)) points")
                    Image(systemName: "square.grid.2x2").imageScale(.medium)
                        .accessibilityHidden(true)
                }
                .help("Icon size")
            }
            if let volumeSpaceText {
                Text(volumeSpaceText)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .task(id: viewModel.currentDirectory) {
            guard let currentDirectory = viewModel.currentDirectory else {
                volumeSpace = nil
                return
            }
            volumeSpace = await volumeSpaceService.space(for: currentDirectory)
        }
    }

    /// An error shows in its own banner above (`OperationErrorBanner`),
    /// not in place of the counts.
    private var statusText: String {
        if let archiveOperationStatus = viewModel.archiveOperationStatus {
            return archiveOperationStatus
        }
        let folderCount = viewModel.items.filter(\.isDirectory).count
        return Self.summary(items: viewModel.items.count, folders: folderCount, selected: viewModel.selectedNodes.count)
    }

    /// "6 items, 1 folder, 5 files", "1 of 2 items, 0 folders, 2 files".
    static func summary(items: Int, folders: Int, selected: Int) -> String {
        func count(_ number: Int, _ singular: String, _ plural: String) -> String {
            "\(number) \(number == 1 ? singular : plural)"
        }
        let base = "\(count(items, "item", "items")), \(count(folders, "folder", "folders")), \(count(items - folders, "file", "files"))"
        return selected > 0 ? "\(selected) of \(base)" : base
    }

    private var volumeSpaceText: String? {
        guard let volumeSpace else { return nil }
        let available = Self.byteFormatter.string(fromByteCount: volumeSpace.availableCapacity)
        let total = Self.byteFormatter.string(fromByteCount: volumeSpace.totalCapacity)
        return "\(available) available of \(total)"
    }
}

/// A failed file operation's message, in a red banner above the status
/// line until dismissed or you go to another folder — it used to replace
/// the status line's text, easy to miss and never read out. VoiceOver
/// announces it when it appears. Show Details opens File Operations, where
/// the failure is listed with what's known and, for a copy or move, Retry.
struct OperationErrorBanner: View {
    var viewModel: FileListViewModel
    let windowViewModel: WindowViewModel

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Show Details") {
                        windowViewModel.showWorkspaceTool(.fileOperations)
                    }
                    .controlSize(.small)
                    .help("Open File Operations, where the failure is listed")
                    Button {
                        viewModel.dismissError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.10))
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Error")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement("Error: \(message)").post()
        }
    }
}
