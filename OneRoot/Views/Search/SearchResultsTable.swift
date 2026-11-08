import AppKit
import SwiftUI

/// Swaps between two `Table` layouts depending on search mode — metadata
/// mode shows Name/Size/Date/Path like the main file list; content mode
/// adds Line/Match columns (grep-style) since a single file can have
/// several matching rows. A plain SwiftUI `Table` is enough here (unlike
/// the main file list's `NSTableView` — see CLAUDE.md's AppKit-tree note)
/// since results don't need drag-and-drop, inline rename, or persisted
/// column state.
struct SearchResultsView: View {
    @Environment(\.appTheme) private var theme
    /// Read so the dates redraw when Settings switches Today/Yesterday.
    @AppStorage(FileDateFormat.usesRelativeDatesKey) private var usesRelativeDates = false
    let results: [SearchResult]
    let mode: SearchMode
    @Binding var selection: Set<SearchResult.ID>


    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // `TableColumnBuilder`'s `if`/`else` (`buildEither`) needs macOS 14.4 —
    // this app's deployment target is 14.0 (CLAUDE.md §2/§8) — so the two
    // layouts are two separate `Table`s picked with a plain `ViewBuilder`
    // `if`/`else` here instead of one `Table` with a conditional column.
    var body: some View {
        if mode == .contents {
            contentTable
        } else {
            metadataTable
        }
    }

    private var contentTable: some View {
        Table(results, selection: $selection) {
            TableColumn("Name") { result in nameCell(result) }
                .width(min: 160, ideal: 220)
            TableColumn("Line") { result in
                Text(result.contentMatch.map { String($0.lineNumber) } ?? "")
            }
            .width(50)
            TableColumn("Match") { result in
                Text(result.contentMatch?.snippet ?? "")
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Path") { result in pathCell(result) }
                .width(min: 160, ideal: 260)
        }
        .contextMenu(forSelectionType: SearchResult.ID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            openAll(ids)
        }
    }

    private var metadataTable: some View {
        Table(results, selection: $selection) {
            TableColumn("Name") { result in nameCell(result) }
                .width(min: 160, ideal: 220)
            TableColumn("Size") { result in
                Text(result.node.isDirectory ? "--" : (result.node.size.map { Self.byteFormatter.string(fromByteCount: $0) } ?? ""))
            }
            .width(80)
            TableColumn("Date Modified") { result in
                Text(result.node.modificationDate.map { FileDateFormat.string(from: $0) } ?? "")
            }
            .width(150)
            TableColumn("Path") { result in pathCell(result) }
                .width(min: 160, ideal: 260)
        }
        .contextMenu(forSelectionType: SearchResult.ID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            openAll(ids)
        }
    }

    private func nameCell(_ result: SearchResult) -> some View {
        HStack(spacing: 4) {
            Image(nsImage: iconImage(for: result.node))
                .resizable()
                .frame(width: 16, height: 16)
            Text(result.node.name)
            if result.isCloudOnly {
                Image(systemName: "icloud.and.arrow.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .help("Not downloaded: only in the cloud so far")
            }
        }
    }

    private func pathCell(_ result: SearchResult) -> some View {
        Text(result.node.url.deletingLastPathComponent().path)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func iconImage(for node: FileNode) -> NSImage {
        ThemedIcons.icon(for: node.url, isFolder: node.isDirectory && !node.isPackage, theme: theme)
    }

    /// Double-click (`Table`'s `primaryAction`). A folder opens in OneRoot
    /// in a new tab — a double-clicked search result is a new place you're
    /// going, not the tab you're already browsing — while a file still just
    /// opens with its default app, same as the main file list.
    private func openAll(_ ids: Set<SearchResult.ID>) {
        for id in ids {
            guard let result = results.first(where: { $0.id == id }) else { continue }
            if result.node.isDirectory {
                NotificationCenter.default.post(name: .revealInOneRoot, object: RevealInOneRootRequest(url: result.node.url, openInNewTab: true))
            } else {
                open(result)
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for ids: Set<SearchResult.ID>) -> some View {
        if let first = ids.first, let result = results.first(where: { $0.id == first }) {
            Button("Open") { open(result) }
            Button("Open in OneRoot") { openInOneRoot(result) }
            Button("Reveal in Finder") { reveal(result) }
            Button("Copy Path") { copyPath(result) }
        }
    }

    private func open(_ result: SearchResult) {
        NSWorkspace.shared.open(result.node.url)
    }

    /// Posts the folder to navigate to — the match itself if it's a folder,
    /// otherwise its containing folder — so `MainWindowView` doesn't need
    /// its own copy of that "is this a folder" branch.
    private func openInOneRoot(_ result: SearchResult) {
        let target = result.node.isDirectory ? result.node.url : result.node.url.deletingLastPathComponent()
        NotificationCenter.default.post(name: .revealInOneRoot, object: RevealInOneRootRequest(url: target, openInNewTab: false))
    }

    private func reveal(_ result: SearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.node.url])
    }

    private func copyPath(_ result: SearchResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.node.url.path, forType: .string)
    }
}
