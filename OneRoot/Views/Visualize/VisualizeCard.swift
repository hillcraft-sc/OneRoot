import AppKit
import SwiftUI

/// The Visualize tool card: what's taking space in the folder you're in.
/// Folders shows a treemap of its items (click a folder to go into it, a
/// file to select it in the list); Types, Age, Tags and Cloud show a
/// stacked bar and the groups as a list — pick one to see its largest
/// files, and click one to find it in the list. Every chart has the same
/// numbers in a labeled list beside it.
struct VisualizeCard: View {
    @Bindable var viewModel: VisualizeViewModel
    let folder: URL?
    var onOpenFolder: (URL) -> Void
    var onReveal: (URL) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visualize")
        .onAppear { viewModel.show(folder, delay: .zero) }
        .onChange(of: folder) { _, newFolder in viewModel.show(newFolder) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .foregroundStyle(theme.accentColor)
            Text("Visualize")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Picker("Breakdown", selection: $viewModel.breakdown) {
                ForEach(VisualizeViewModel.Breakdown.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .onChange(of: viewModel.breakdown) { _, _ in viewModel.selectedGroup = nil }
            if viewModel.isScanning {
                Button("Stop") { viewModel.stop() }
                    .controlSize(.small)
                    .help("Stop scanning — what's been counted so far stays")
            } else {
                Button {
                    viewModel.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(folder == nil)
                .help("Scan again")
                .accessibilityLabel("Rescan")
            }
            HelpButton(topic: .visualize, compact: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            message(error, systemImage: "exclamationmark.triangle")
        } else if let report = viewModel.report {
            VStack(alignment: .leading, spacing: 8) {
                summary(report)
                switch viewModel.breakdown {
                case .folders:
                    FoldersBreakdown(report: report, isDark: theme.isDark, onOpenFolder: onOpenFolder, onReveal: onReveal)
                default:
                    GroupsBreakdown(
                        groups: groups(report),
                        emptyMessage: emptyMessage(report),
                        selectedGroup: $viewModel.selectedGroup,
                        isDark: theme.isDark,
                        onReveal: onReveal
                    )
                }
            }
        } else if viewModel.isScanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning\u{2026}").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            message("Open a folder to see what's taking up space in it.", systemImage: "chart.pie")
        }
    }

    private func summary(_ report: StorageReport) -> some View {
        HStack(spacing: 6) {
            if viewModel.isScanning {
                ProgressView().controlSize(.mini)
            }
            Text(summaryText(report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func summaryText(_ report: StorageReport) -> String {
        var parts = [
            FileOperationText.bytes(report.totalSize),
            report.fileCount == 1 ? "1 file" : "\(report.fileCount.formatted()) files",
            report.folderCount == 1 ? "1 folder" : "\(report.folderCount.formatted()) folders",
        ]
        if report.unreadableCount > 0 {
            parts.append("\(report.unreadableCount.formatted()) couldn't be read")
        }
        let prefix = viewModel.isScanning ? "Scanning \(FileOperationText.shortPath(report.root))\u{2026} so far " : "\(FileOperationText.shortPath(report.root)): "
        return prefix + parts.joined(separator: " \u{00B7} ")
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Groups

    private func groups(_ report: StorageReport) -> [VisualizeGroup] {
        let dark = theme.isDark
        switch viewModel.breakdown {
        case .folders:
            return []
        case .types:
            return StorageCategory.allCases.enumerated().compactMap { index, category in
                guard let bucket = report.categories[category], bucket.count > 0 else { return nil }
                return VisualizeGroup(id: category.rawValue, title: category.title, systemImage: category.systemImage, bucket: bucket, color: VisualizePalette.series(index, dark: dark))
            }
        case .age:
            let ordered: [StorageAge] = [.thisWeek, .thisMonth, .thisYear, .older]
            var result = ordered.enumerated().compactMap { index, age -> VisualizeGroup? in
                guard let bucket = report.ages[age], bucket.count > 0 else { return nil }
                return VisualizeGroup(id: "\(age)", title: age.title, systemImage: "clock", bucket: bucket, color: VisualizePalette.ordinal(index, of: ordered.count, dark: dark))
            }
            if let unknown = report.ages[.unknown], unknown.count > 0 {
                result.append(VisualizeGroup(id: "unknown", title: StorageAge.unknown.title, systemImage: "clock", bucket: unknown, color: VisualizePalette.neutral(dark: dark)))
            }
            return result
        case .tags:
            // Each tag in its own Finder color — the color is the tag's.
            var result = report.tags
                .sorted { $0.value.size != $1.value.size ? $0.value.size > $1.value.size : $0.key < $1.key }
                .map { tag, bucket in
                    VisualizeGroup(id: "tag:" + tag, title: tag, systemImage: "tag", bucket: bucket, color: Color(nsColor: TagColors.color(for: tag)))
                }
            if report.untagged.count > 0 {
                result.append(VisualizeGroup(id: "untagged", title: "No tags", systemImage: "tag.slash", bucket: report.untagged, color: VisualizePalette.neutral(dark: dark)))
            }
            return result
        case .cloud:
            guard report.hasCloudItems else { return [] }
            return StorageCloudState.allCases.enumerated().compactMap { index, state in
                guard let bucket = report.cloud[state], bucket.count > 0 else { return nil }
                let color = state == .notInCloud ? VisualizePalette.neutral(dark: dark) : VisualizePalette.series(index, dark: dark)
                let symbol = state == .cloudOnly ? "icloud" : (state == .downloaded ? "icloud.and.arrow.down" : "internaldrive")
                return VisualizeGroup(id: "\(state)", title: state.title, systemImage: symbol, bucket: bucket, color: color)
            }
        }
    }

    private func emptyMessage(_ report: StorageReport) -> String {
        switch viewModel.breakdown {
        case .cloud: return "Nothing here is synced by a cloud provider."
        case .tags: return "No tagged files here."
        default: return report.isComplete ? "No files here." : "Nothing counted yet."
        }
    }
}

/// One slice of a breakdown: a kind of file, an age, a tag, a cloud state.
struct VisualizeGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let bucket: StorageBucket
    let color: Color
}

// MARK: - Folders

/// The folder's items as a treemap — area is size — beside the same items
/// as a list. Folders are blue, files gray; the smallest are folded into
/// "Other" so every block is big enough to read and click.
private struct FoldersBreakdown: View {
    let report: StorageReport
    let isDark: Bool
    var onOpenFolder: (URL) -> Void
    var onReveal: (URL) -> Void

    private static let maxBlocks = 14
    /// Anything smaller than this share is too thin to read or click, so
    /// it goes into "Other" too.
    private static let minShare = 0.01

    private var blocks: [Block] {
        let entries = report.children.filter { $0.size > 0 }
        let minimum = Int64(Double(report.totalSize) * Self.minShare)
        let shown = entries.prefix(Self.maxBlocks).prefix { $0.size >= minimum }
        var result = shown.map { Block(entry: $0, otherCount: 0, size: $0.size) }
        let rest = entries.dropFirst(shown.count)
        if !rest.isEmpty {
            result.append(Block(entry: nil, otherCount: rest.count, size: rest.reduce(0) { $0 + $1.size }))
        }
        return result
    }

    var body: some View {
        let blocks = blocks
        if blocks.isEmpty {
            Text(report.isComplete ? "Nothing in this folder takes up space." : "Nothing counted yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 12) {
                treemap(blocks)
                    .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                list(blocks)
                    .frame(width: 280)
            }
        }
    }

    private func treemap(_ blocks: [Block]) -> some View {
        GeometryReader { proxy in
            let rects = TreemapLayout.rects(for: blocks.map { Double($0.size) }, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    let rect = rects[index].insetBy(dx: 1, dy: 1) // the 2px gap between blocks
                    if rect.width > 1, rect.height > 1 {
                        blockView(block, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .accessibilityHidden(true) // the list beside it carries the same items
    }

    private func blockView(_ block: Block, size: CGSize) -> some View {
        let fill = color(block)
        let showsLabel = size.width > 56 && size.height > 30
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay(alignment: .topLeading) {
                if showsLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(FileOperationText.bytes(block.size))
                            .font(.system(size: 10))
                            .opacity(0.85)
                    }
                    .foregroundStyle(block.isFolder ? Color.white : Color.primary)
                    .padding(5)
                }
            }
            .contentShape(Rectangle())
            .help("\(block.title) \u{2014} \(FileOperationText.bytes(block.size)) (\(percent(block.size)))")
            .onTapGesture { choose(block) }
    }

    private func list(_ blocks: [Block]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(blocks) { block in
                    Button {
                        choose(block)
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(color(block)).frame(width: 8, height: 8)
                            Image(systemName: block.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(block.title).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(FileOperationText.bytes(block.size)).foregroundStyle(.secondary).monospacedDigit()
                            Text(percent(block.size)).foregroundStyle(.tertiary).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(block.entry == nil)
                    .help(block.entry.map { $0.isDirectory ? "Open \($0.name)" : "Select \($0.name) in the list" } ?? "")
                    .accessibilityLabel("\(block.title), \(FileOperationText.bytes(block.size)), \(percent(block.size))")
                    .accessibilityHint(block.entry.map { $0.isDirectory ? "Opens the folder" : "Selects the file in the list" } ?? "")
                }
            }
        }
    }

    private func choose(_ block: Block) {
        guard let entry = block.entry else { return }
        if entry.isDirectory {
            onOpenFolder(entry.url)
        } else {
            onReveal(entry.url)
        }
    }

    private func color(_ block: Block) -> Color {
        block.isFolder ? VisualizePalette.series(0, dark: isDark) : VisualizePalette.neutral(dark: isDark).opacity(block.entry == nil ? 0.55 : 1)
    }

    private func percent(_ size: Int64) -> String {
        guard report.totalSize > 0 else { return "" }
        let value = Double(size) / Double(report.totalSize) * 100
        return value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }

    struct Block: Identifiable {
        let entry: StorageEntry?
        let otherCount: Int
        let size: Int64
        var id: String { entry?.url.path ?? "other" }
        var isFolder: Bool { entry?.isDirectory == true }
        var title: String { entry?.name ?? "\(otherCount) more items" }
        var symbol: String { entry == nil ? "ellipsis" : (isFolder ? "folder" : "doc") }
    }
}

// MARK: - Types, Age, Tags, Cloud

/// A stacked bar of the groups (in their fixed order, so colors stay put),
/// the groups as a list, and the chosen group's largest files.
private struct GroupsBreakdown: View {
    let groups: [VisualizeGroup]
    let emptyMessage: String
    @Binding var selectedGroup: String?
    let isDark: Bool
    var onReveal: (URL) -> Void

    private var total: Int64 { groups.reduce(0) { $0 + $1.bucket.size } }

    /// The chosen group, or the largest until one is chosen.
    private var current: VisualizeGroup? {
        groups.first { $0.id == selectedGroup } ?? groups.max { $0.bucket.size < $1.bucket.size }
    }

    var body: some View {
        if groups.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                stackedBar
                    .frame(height: 14)
                HStack(alignment: .top, spacing: 12) {
                    groupList
                        .frame(minWidth: 220, maxWidth: .infinity)
                    largestFiles
                        .frame(minWidth: 240, maxWidth: .infinity)
                }
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(groups.count - 1, 0)) * 2
            let usable = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(groups) { group in
                    let share = total > 0 ? CGFloat(Double(group.bucket.size) / Double(total)) : 0
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(group.color)
                        .frame(width: max(usable * share, share > 0 ? 2 : 0))
                        .opacity(current?.id == group.id ? 1 : 0.75)
                        .help("\(group.title) \u{2014} \(FileOperationText.bytes(group.bucket.size)) (\(percent(group.bucket.size)))")
                        .onTapGesture { selectedGroup = group.id }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var groupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups) { group in
                    let isCurrent = current?.id == group.id
                    Button {
                        selectedGroup = group.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(group.color).frame(width: 8, height: 8)
                            Image(systemName: group.systemImage).foregroundStyle(.secondary).frame(width: 14)
                            Text(group.title).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(group.bucket.count == 1 ? "1 item" : "\(group.bucket.count.formatted()) items")
                                .foregroundStyle(.tertiary)
                            Text(FileOperationText.bytes(group.bucket.size)).foregroundStyle(.secondary).monospacedDigit()
                            Text(percent(group.bucket.size)).foregroundStyle(.tertiary).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                        .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(isCurrent ? Color.primary.opacity(isDark ? 0.12 : 0.07) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.title), \(group.bucket.count) items, \(FileOperationText.bytes(group.bucket.size)), \(percent(group.bucket.size))")
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var largestFiles: some View {
        if let current {
            VStack(alignment: .leading, spacing: 4) {
                Text("Largest in \(current.title)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(current.bucket.largest) { file in
                            Button {
                                onReveal(file.url)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                        .resizable()
                                        .frame(width: 14, height: 14)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                        Text(FileOperationText.shortPath(file.url.deletingLastPathComponent()))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                    Spacer(minLength: 4)
                                    Text(FileOperationText.bytes(file.size)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.system(size: 11))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Show \(file.url.lastPathComponent) in the list")
                            .accessibilityLabel("\(file.url.lastPathComponent), \(FileOperationText.bytes(file.size))")
                            .accessibilityHint("Shows the file in the list")
                        }
                    }
                }
            }
        }
    }

    private func percent(_ size: Int64) -> String {
        guard total > 0 else { return "" }
        let value = Double(size) / Double(total) * 100
        return value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }
}
