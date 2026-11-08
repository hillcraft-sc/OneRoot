import AppKit
import SwiftUI

/// The Inspector card's content: what's selected in the focused pane — or,
/// with nothing selected, the folder you're in. A large preview, the name,
/// Open (in the default app, or another), Share and Copy Path, then the
/// details OneRoot really knows. Nothing is shown that isn't read from the
/// file: no invented versions, activity, or related files.
///
/// Loading is debounced and tied to the selection (`.task(id:)`), so
/// arrowing through a folder doesn't render every preview it passes, and a
/// slow lookup for an item you've moved past can't land on the current one.
struct InspectorView: View {
    var viewModel: FileListViewModel

    /// What's actually being shown — trails the selection by a moment.
    @State private var shown: [FileNode] = []
    @State private var details = ItemDetails()
    @State private var defaultApp: URL?
    /// Which tab of details is showing — kept as you move between items,
    /// and per window tab (`Tab.inspectorSection`).
    @Binding var section: InspectorSection
    /// The shown item's tags — updated as soon as you change them, before
    /// the folder reloads.
    @State private var tags: [String] = []
    /// Markdown files: raw text (Quick Look) or rendered — raw by default,
    /// and remembered.
    @AppStorage("com.oneroot.inspector.showsRenderedMarkdown") private var showsRenderedMarkdown = false
    @State private var tagError: String?
    /// Read so the dates redraw when Settings switches Today/Yesterday.
    @AppStorage(FileDateFormat.usesRelativeDatesKey) private var usesRelativeDates = false
    private var pinned = PinnedLocationsStore.shared
    @Environment(\.appTheme) private var theme

    /// `shown`, but the selection's current copies of those items: a reload
    /// (after tagging, say) replaces them with fresh ones under the same
    /// URLs, which the `.task` below doesn't treat as a new selection.
    private var displayed: [FileNode] {
        Self.displayed(shown: shown, current: viewModel.selectedNodes)
    }

    /// The selection's current copies when they're the same items as
    /// `shown` (in order), else `shown` — a different selection waits for
    /// the debounced `.task` to take over.
    static func displayed(shown: [FileNode], current: [FileNode]) -> [FileNode] {
        guard current.count == shown.count, zip(current, shown).allSatisfy({ $0.url == $1.url }) else { return shown }
        return current
    }

    var body: some View {
        let displayed = displayed
        Group {
            switch displayed.count {
            case 0:
                currentFolder
            case 1:
                single(displayed[0])
            default:
                multiple(displayed)
            }
        }
        // One item's tags changed elsewhere (the right-click Tags menu):
        // show them.
        .onChange(of: displayed.first?.tags) { _, newTags in
            guard displayed.count == 1, let newTags, newTags != tags else { return }
            tags = newTags
            tagError = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The folder too: with nothing selected, moving to another folder
        // must refresh its summary.
        .task(id: [viewModel.currentDirectory] + viewModel.selectedNodes.map(\.url)) {
            let selection = viewModel.selectedNodes
            // Long enough to skip over items while a key is held down,
            // short enough to feel immediate on a single click.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            shown = selection
            tags = selection.count == 1 ? selection[0].tags : []
            tagError = nil
            details = ItemDetails()
            defaultApp = nil
            let target = selection.count == 1 ? selection[0] : nil
            let url = target?.url ?? viewModel.currentDirectory
            guard let url else { return }
            let isFolder = target.map { $0.isDirectory && !$0.isPackage } ?? true
            let loaded = await ItemDetailsService().details(for: url, isDirectory: isFolder)
            guard !Task.isCancelled else { return }
            details = loaded
            if let target, !isFolder {
                defaultApp = NSWorkspace.shared.urlForApplication(toOpen: target.url)
            }
        }
    }

    // MARK: One item

    private func single(_ node: FileNode) -> some View {
        let isFolder = node.isDirectory && !node.isPackage
        let isMarkdown = !node.isDirectory && QuickActionCatalog.markdownExtensions.contains(node.fileExtension.lowercased())
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isMarkdown {
                    Picker("Markdown preview", selection: $showsRenderedMarkdown) {
                        Text("Raw").tag(false)
                        Text("Rendered").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help("Show the Markdown as written, or as it reads")
                    .accessibilityLabel("Markdown preview")
                }
                Group {
                    // Quick Look shows the system's own folder; a folder
                    // gets the theme's, like everywhere else.
                    if isFolder {
                        Image(nsImage: ThemedIcons.folder(size: 150, color: theme.icons.folder))
                            .accessibilityHidden(true)
                    } else if isMarkdown, showsRenderedMarkdown {
                        MarkdownPreview(url: node.url)
                    } else {
                        QuickLookPreview(url: node.url)
                    }
                }
                    // A rendered page needs more room to be worth reading.
                    .frame(height: isMarkdown ? 280 : 190)
                    .frame(maxWidth: .infinity)
                    .background(theme.surfaces?.field.color ?? Color(nsColor: .underPageBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: ThemedIcons.icon(for: node.url, isFolder: isFolder, theme: theme, size: 36))
                        .resizable()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle(node))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                openButton(node, isFolder: isFolder)
                actionRow(node, isFolder: isFolder)

                Picker("Section", selection: $section) {
                    ForEach(InspectorSection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                switch section {
                case .details: generalInfo(node, isFolder: isFolder)
                case .moreInfo: moreInfo
                case .permissions: permissions
                }
            }
            .padding(14)
        }
    }

    private func subtitle(_ node: FileNode) -> String {
        if node.isDirectory && !node.isPackage {
            guard let count = details.itemCount else { return "Folder" }
            return count == 1 ? "Folder • 1 item" : "Folder • \(count) items"
        }
        let kind = node.kind ?? "File"
        guard let size = node.size else { return kind }
        return "\(kind) • \(Self.byteFormatter.string(fromByteCount: size))"
    }

    /// Opens in the default app (named, like the design's "Open in Figma")
    /// — a folder opens right here — with a menu of other ways to open it on
    /// the chevron. One look for both, always the accent color.
    private func openButton(_ node: FileNode, isFolder: Bool) -> some View {
        let appName = defaultApp.map(Self.appName)
        return SplitOpenButton(
            title: isFolder ? "Open" : (appName.map { "Open in \($0)" } ?? "Open"),
            accent: theme.accentColor,
            open: {
                if isFolder {
                    viewModel.navigate(to: node.url)
                } else {
                    NSWorkspace.shared.open(node.url)
                }
            },
            menuEntries: { openWithEntries(node, isFolder: isFolder) }
        )
    }

    /// Built when the chevron is clicked, for the item selected then — so
    /// it always lists the apps for *this* file's type.
    private func openWithEntries(_ node: FileNode, isFolder: Bool) -> [SplitOpenButton.Entry] {
        var entries: [SplitOpenButton.Entry] = []
        if isFolder {
            entries.append(.init(title: "Open in New Tab", icon: nil) { viewModel.requestOpenInNewTab(node.url) })
            entries.append(.init(title: "Open in Terminal", icon: nil) { openInTerminal(node.url) })
            entries.append(.separator)
        }
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: node.url)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: node.url)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        for app in apps {
            let title = Self.appName(app) + (app == defaultApp && !isFolder ? " (default)" : "")
            entries.append(.init(title: title, icon: NSWorkspace.shared.icon(forFile: app.path)) {
                NSWorkspace.shared.open([node.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            })
        }
        if apps.isEmpty && !isFolder {
            entries.append(.init(title: "No apps can open this", icon: nil, action: nil))
        }
        return entries
    }

    private static func appName(_ appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Share, Copy Path, More — or for a folder, New Tab and Pin first
    /// (Share moves into More).
    private func actionRow(_ node: FileNode, isFolder: Bool) -> some View {
        HStack(spacing: 0) {
            if isFolder {
                Button {
                    viewModel.requestOpenInNewTab(node.url)
                } label: {
                    actionLabel("New Tab", "plus.square.on.square")
                }
                .buttonStyle(.plain)
                .help("Open this folder in a new tab")
                let isPinned = pinned.isPinned(node.url)
                Button {
                    pinned.toggle(node.url)
                } label: {
                    actionLabel(isPinned ? "Unpin" : "Pin", isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Remove from Pinned in the sidebar" : "Add to Pinned in the sidebar")
            } else {
                ShareLink(item: node.url) {
                    actionLabel("Share", "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            Button {
                viewModel.copyPath(node)
            } label: {
                actionLabel("Copy Path", "link")
            }
            .buttonStyle(.plain)
            Menu {
                if isFolder {
                    ShareLink("Share…", item: node.url)
                    AddToWorkspaceMenu(folder: node.url)
                }
                Button("Quick Look") { viewModel.triggerQuickLook() }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Button("Open in Terminal") {
                    openInTerminal(node.isDirectory ? node.url : node.url.deletingLastPathComponent())
                }
                Divider()
                Button("Rename…") { viewModel.promptRename(node) }
                Button("Move to Trash", role: .destructive) {
                    if TrashConfirmation.confirm([node.name]) { viewModel.moveToTrash([node]) }
                }
            } label: {
                actionLabel("More", "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
        }
    }

    private func actionLabel(_ title: String, _ systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(theme.accentColor)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: Details tabs

    /// Get Info's General section, as plain rows.
    private func generalInfo(_ node: FileNode, isFolder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow("Kind", details.isAlias ? "Alias" : (isFolder ? "Folder" : (node.kind ?? "Document")))
            if isFolder {
                if let count = details.itemCount {
                    InfoRow("Contains", count == 1 ? "1 item" : "\(count) items")
                }
                if let size = viewModel.folderSizes[node.url] {
                    InfoRow("Size", Self.sizeWithBytes(size))
                } else {
                    InfoRow("Size", viewModel.calculatingFolderSizes.contains(node.url) || FolderSizePreferenceStore.shared.calculateAll ? "Calculating…" : "—") {
                        if !viewModel.calculatingFolderSizes.contains(node.url), !FolderSizePreferenceStore.shared.calculateAll {
                            Button("Calculate") { viewModel.calculateFolderSizes([node]) }
                                .controlSize(.small)
                        }
                    }
                }
            } else if let size = node.size {
                InfoRow("Size", Self.sizeWithBytes(size))
                if let onDisk = details.sizeOnDisk, onDisk != size {
                    InfoRow("On disk", Self.byteFormatter.string(fromByteCount: onDisk))
                }
            }
            if let cloud = details.cloud {
                InfoRow("Cloud", cloud.description)
            }
            Divider().padding(.vertical, 6)
            if let created = node.creationDate { InfoRow("Created", FileDateFormat.string(from: created)) }
            if let modified = node.modificationDate { InfoRow("Modified", FileDateFormat.string(from: modified)) }
            if let opened = node.lastOpenedDate { InfoRow("Last opened", FileDateFormat.string(from: opened)) }
            if let added = details.dateAdded ?? node.dateAdded { InfoRow("Added", FileDateFormat.string(from: added)) }
            Divider().padding(.vertical, 6)
            // Reveal in Finder is under More.
            InfoRow("Where", Self.shortLocation(node.url.deletingLastPathComponent()))
            if let destination = details.linkDestination {
                InfoRow("Original", Self.shortLocation(URL(fileURLWithPath: destination)))
            }
            InfoRow("Tags") {
                VStack(alignment: .leading, spacing: 4) {
                    TagEditor(
                        tags: tags,
                        suggestions: TagService.suggestions(
                            standard: Array(NSWorkspace.shared.fileLabels.dropFirst()),
                            inFolder: viewModel.tagsInFolder,
                            excluding: tags
                        ),
                        onChange: { applyTags($0, to: node) }
                    )
                    if let tagError {
                        Text(tagError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Shows the change at once and writes it; puts the old tags back if
    /// writing fails.
    private func applyTags(_ newTags: [String], to node: FileNode) {
        let previous = tags
        tags = newTags
        tagError = nil
        Task {
            if let error = await viewModel.setTags(newTags, for: node) {
                tags = previous
                tagError = error
            }
        }
    }

    /// Get Info's More Info and Comments: what Spotlight knows about the
    /// content — dimensions, duration, pages, authors, where a download
    /// came from.
    @ViewBuilder
    private var moreInfo: some View {
        let rows = moreInfoRows
        if rows.isEmpty && details.finderComment == nil {
            Text("No more information for this kind of item.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.0) { label, value in InfoRow(label, value) }
                if !details.whereFroms.isEmpty {
                    InfoRow("Downloaded from") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(details.whereFroms, id: \.self) { source in
                                Text(ItemDetailsService.displaySource(source))
                                    .textSelection(.enabled)
                                    .help(source)
                            }
                        }
                    }
                }
                if let comment = details.finderComment {
                    InfoRow("Comments", comment)
                }
            }
        }
    }

    private var moreInfoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let width = details.pixelWidth, let height = details.pixelHeight {
            rows.append(("Dimensions", "\(width) \u{00D7} \(height)"))
        }
        if let dpi = details.resolutionDPI { rows.append(("Resolution", "\(dpi) dpi")) }
        if let colorSpace = details.colorSpace { rows.append(("Color space", colorSpace)) }
        if let duration = details.durationSeconds, duration > 0 {
            rows.append(("Duration", ItemDetailsService.formatDuration(duration)))
        }
        if !details.codecs.isEmpty { rows.append(("Codecs", details.codecs.joined(separator: ", "))) }
        if let pages = details.pageCount { rows.append(("Pages", "\(pages)")) }
        if let title = details.title { rows.append(("Title", title)) }
        if !details.authors.isEmpty { rows.append(("Authors", details.authors.joined(separator: ", "))) }
        if let version = details.version { rows.append(("Version", version)) }
        return rows
    }

    /// Get Info's Sharing & Permissions, read-only.
    @ViewBuilder
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let owner = details.owner {
                InfoRow("Owner", owner == NSUserName() ? "\(owner) (you)" : owner)
            }
            if let group = details.group { InfoRow("Group", group) }
            if let mode = details.posixPermissions {
                Divider().padding(.vertical, 6)
                InfoRow(details.owner.map { "\($0)" } ?? "Owner", ItemDetailsService.access(mode, for: .owner))
                InfoRow(details.group ?? "Group", ItemDetailsService.access(mode, for: .group))
                InfoRow("Everyone", ItemDetailsService.access(mode, for: .everyone))
            }
            if details.isLocked || details.hasHiddenExtension {
                Divider().padding(.vertical, 6)
            }
            if details.isLocked { InfoRow("Locked", "Yes — can't be changed or moved to the Trash") }
            if details.hasHiddenExtension { InfoRow("Extension", "Hidden in Finder") }
        }
    }

    /// "8.2 MB (8,204,331 bytes)" — readable and exact, like Get Info.
    private static func sizeWithBytes(_ bytes: Int64) -> String {
        let exact = NumberFormatter.localizedString(from: NSNumber(value: bytes), number: .decimal)
        return "\(byteFormatter.string(fromByteCount: bytes)) (\(exact) bytes)"
    }

    // MARK: Several items

    private func multiple(_ nodes: [FileNode]) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: nodes.allSatisfy { $0.isDirectory && !$0.isPackage }
                ? ThemedIcons.folder(size: 96, color: theme.icons.folder)
                : (NSWorkspace.shared.icon(forFiles: nodes.map(\.url.path)) ?? NSWorkspace.shared.icon(for: .item)))
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("\(nodes.count) items")
                .font(.headline)
            let fileBytes = nodes.filter { !$0.isDirectory }.compactMap(\.size).reduce(0, +)
            let folderCount = nodes.filter(\.isDirectory).count
            Text(summary(fileBytes: fileBytes, folderCount: folderCount))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Compress") { viewModel.compressSelection(nodes) }
                Button("Rename…") { viewModel.promptBatchRename(nodes) }
            }
            .controlSize(.small)
            Divider().padding(.vertical, 4)
            MultiTagEditor(viewModel: viewModel, nodes: nodes)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func summary(fileBytes: Int64, folderCount: Int) -> String {
        let size = Self.byteFormatter.string(fromByteCount: fileBytes)
        switch folderCount {
        case 0: return size
        case 1: return "\(size) in files, plus 1 folder"
        default: return "\(size) in files, plus \(folderCount) folders"
        }
    }

    // MARK: Nothing selected

    /// The folder you're in, quietly — a summary, not a call to action.
    private var currentFolder: some View {
        VStack(spacing: 8) {
            if let url = viewModel.currentDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.icons.folder.color)
                    .accessibilityHidden(true)
                Text(url.friendlyFolderName)
                    .font(.headline)
                if let count = details.itemCount {
                    Text(count == 1 ? "1 item" : "\(count) items")
                        .foregroundStyle(.secondary)
                }
                Text(Self.shortLocation(url.deletingLastPathComponent()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                // The folder you're in, the same as a selected one's.
                HStack(spacing: 0) {
                    let isPinned = pinned.isPinned(url)
                    Button {
                        pinned.toggle(url)
                    } label: {
                        actionLabel(isPinned ? "Unpin" : "Pin", isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "Remove this folder from Pinned in the sidebar" : "Add this folder to Pinned in the sidebar")
                    Button {
                        viewModel.copyPaths([url])
                    } label: {
                        actionLabel("Copy Path", "link")
                    }
                    .buttonStyle(.plain)
                    .help("Copy this folder's full path")
                    Button {
                        openInTerminal(url)
                    } label: {
                        actionLabel("Terminal", "terminal")
                    }
                    .buttonStyle(.plain)
                    .help("Open this folder in Terminal")
                    Menu {
                        AddToWorkspaceMenu(folder: url)
                        ShareLink("Share\u{2026}", item: url)
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } label: {
                        actionLabel("More", "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .frame(maxWidth: .infinity)
                    .help("Add to Workspace, Share, Reveal in Finder")
                }
                .padding(.top, 10)
                Text("Select something to see a preview and its details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    /// `~/Documents/Projects` rather than the full `/Users/…` path.
    static func shortLocation(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == home { return "Home folder" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

}

/// A filled accent button with a chevron part, like a split button: the
/// main part opens, the chevron shows a menu built on click (AppKit's, so
/// it's always current). SwiftUI's own menu-button ignores the prominent
/// style, which is why this isn't one.
private struct SplitOpenButton: View {
    struct Entry {
        let title: String
        let icon: NSImage?
        let action: (() -> Void)?

        static let separator = Entry(title: "", icon: nil, action: nil)
    }

    let title: String
    let accent: Color
    let open: () -> Void
    let menuEntries: () -> [Entry]

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1, height: 16)
            Button(action: showMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .help("Open With")
            .accessibilityLabel("Open With")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(height: 30)
        .background(accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func showMenu() {
        let menu = NSMenu()
        for entry in menuEntries() {
            if entry.title.isEmpty {
                menu.addItem(.separator())
                continue
            }
            let item = ClosureMenuItem(title: entry.title, handler: entry.action)
            item.image = entry.icon
            item.image?.size = NSSize(width: 16, height: 16)
            item.isEnabled = entry.action != nil
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// An `NSMenuItem` that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler?()
    }
}

/// The Inspector's tabs of details.
/// One label/value line: a quiet label in a fixed column, the value in
/// full (selectable, wrapping), and an optional control after it.
private struct InfoRow<Value: View, Accessory: View>: View {
    let label: String
    let value: Value
    let accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            value
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .font(.callout)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Value == AnyView {
    init(_ label: String, @ViewBuilder value: () -> some View) where Accessory == EmptyView {
        self.label = label
        self.value = AnyView(value())
        self.accessory = EmptyView()
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, _ text: String) where Accessory == EmptyView {
        self.init(label, text) { EmptyView() }
    }

    init(_ label: String, _ text: String, @ViewBuilder accessory: () -> Accessory) {
        self.label = label
        self.value = Text(text)
        self.accessory = accessory()
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The Inspector's Tags row: each tag with a remove button, then **+** for
/// a standard tag, one already used in this folder, or a new name.
private struct TagEditor: View {
    let tags: [String]
    let suggestions: [String]
    let onChange: ([String]) -> Void
    @State private var isAddingNew = false
    @State private var newTag = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowRow(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 1) {
                        TagChip(tag: tag)
                        Button {
                            onChange(TagService.removing(tag, from: tags))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove \u{201C}\(tag)\u{201D}")
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
                Menu {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag) { onChange(TagService.adding(tag, to: tags)) }
                    }
                    if !suggestions.isEmpty { Divider() }
                    Button("New Tag\u{2026}") {
                        isAddingNew = true
                        DispatchQueue.main.async { isFieldFocused = true }
                    }
                } label: {
                    Label(tags.isEmpty ? "Add Tag" : "Add", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a tag")
                .accessibilityLabel("Add Tag")
            }
            if isAddingNew {
                TextField("New tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($isFieldFocused)
                    .onSubmit { commitNewTag() }
                    .onExitCommand { cancelNewTag() }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { cancelNewTag() }
                    }
            }
        }
    }

    private func commitNewTag() {
        let name = newTag
        cancelNewTag()
        let updated = TagService.adding(name, to: tags)
        if updated != tags { onChange(updated) }
    }

    private func cancelNewTag() {
        isAddingNew = false
        newTag = ""
    }
}

/// Tags for several selected items at once: each tag they carry, marked
/// when only some have it ("2 of 5", with Add to All), ✕ to take it off
/// them all, and Add Tag to put one on them all. Each item keeps its other
/// tags.
private struct MultiTagEditor: View {
    var viewModel: FileListViewModel
    let nodes: [FileNode]
    @State private var error: String?
    @State private var isAddingNew = false
    @State private var newTag = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let usage = TagService.usage(in: nodes.map(\.tags))
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(usage, id: \.tag) { item in
                HStack(spacing: 6) {
                    TagChip(tag: item.tag)
                    if item.count < nodes.count {
                        Text("\(item.count) of \(nodes.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Add to All") { apply(item.tag, adding: true) }
                            .controlSize(.mini)
                            .help("Put \u{201C}\(item.tag)\u{201D} on every selected item")
                            .accessibilityLabel("Add \(item.tag) to all \(nodes.count) items")
                    }
                    Spacer(minLength: 4)
                    Button {
                        apply(item.tag, adding: false)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Take \u{201C}\(item.tag)\u{201D} off every selected item")
                    .accessibilityLabel("Remove \(item.tag) from all items")
                }
                .accessibilityElement(children: .contain)
            }
            Menu {
                let suggestions = TagService.suggestions(
                    standard: Array(NSWorkspace.shared.fileLabels.dropFirst()),
                    inFolder: viewModel.tagsInFolder,
                    excluding: usage.filter { $0.count == nodes.count }.map(\.tag)
                )
                ForEach(suggestions, id: \.self) { tag in
                    Button(tag) { apply(tag, adding: true) }
                }
                if !suggestions.isEmpty { Divider() }
                Button("New Tag\u{2026}") {
                    isAddingNew = true
                    DispatchQueue.main.async { isFieldFocused = true }
                }
            } label: {
                Label("Add Tag to All", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Put a tag on every selected item")
            if isAddingNew {
                TextField("New tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($isFieldFocused)
                    .onSubmit {
                        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        newTag = ""
                        isAddingNew = false
                        if !tag.isEmpty { apply(tag, adding: true) }
                    }
                    .onExitCommand {
                        newTag = ""
                        isAddingNew = false
                    }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func apply(_ tag: String, adding: Bool) {
        error = nil
        let nodes = nodes
        Task { error = await viewModel.setTag(tag, adding: adding, on: nodes) }
    }
}
