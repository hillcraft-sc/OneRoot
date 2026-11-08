import Adwaita
import CAdwaita
import Foundation
import Observation
@testable import OneRoot

/// The Visualize panel: what is taking space in the folder you're in, over
/// the shared `VisualizeViewModel` and `StorageScanner`. Folders lists the
/// folder's items by size; Types, Age, Tags and Cloud list the groups with
/// their largest files. Every row has its number as text next to its bar.
/// Sits above the status bar, hidden until opened (Ctrl+Alt+V); it scans
/// only while shown, and follows the active pane's folder.
@MainActor
final class VisualizePanel {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)

    /// Go into this folder in the active pane.
    var onOpenFolder: ((URL) -> Void)?
    /// Select this file (or folder) in its folder.
    var onReveal: ((URL) -> Void)?

    private let viewModel = VisualizeViewModel()
    private let summaryLabel = Label("")
    private let list = ListBox()
    private let scroller = ScrolledWindow()
    private let stopButton = Button(label: "Stop")
    private let rescanButton = Button(iconName: "view-refresh-symbolic")
    private let spinner = Image(iconName: "content-loading-symbolic")
    private var breakdownButtons: [(VisualizeViewModel.Breakdown, ToggleButton)] = []
    private var watches: [ObservationWatch] = []
    private var folder: URL?
    private var isSyncing = false
    /// The Folders treemap currently shown (kept alive with its row).
    private var treemapView: TreemapView?
    private var barView: StackedBarView?
    private var darkConnection: SignalConnection?
    private(set) var isShown = false

    init() {
        widget.addCSSClass("oneroot-operations")
        widget.setAccessibleLabel("Visualize")
        widget.visible = false

        let title = Label("Visualize")
        title.addCSSClass("heading")
        title.xalign = 0

        let segments = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        segments.addCSSClass(.linked)
        var first: ToggleButton?
        for breakdown in VisualizeViewModel.Breakdown.allCases {
            let button = ToggleButton(label: breakdown.title)
            button.addCSSClass("caption")
            button.setAccessibleLabel("Show \(breakdown.title)")
            if let first { button.setGroup(first) } else { first = button }
            button.active = breakdown == viewModel.breakdown
            button.onToggled { [weak self] in
                guard let self, !self.isSyncing, button.active else { return }
                self.viewModel.breakdown = breakdown
                self.viewModel.selectedGroup = nil
            }
            segments.append(button)
            breakdownButtons.append((breakdown, button))
        }

        spinner.pixelSize = 14
        spinner.visible = false
        stopButton.addCSSClass(.flat)
        stopButton.tooltipText = "Stop scanning \u{2014} what has been counted so far stays"
        stopButton.onClicked { [weak self] in self?.viewModel.stop() }
        rescanButton.addCSSClass(.flat)
        rescanButton.tooltipText = "Scan again"
        rescanButton.setAccessibleLabel("Rescan")
        rescanButton.onClicked { [weak self] in self?.viewModel.rescan() }
        let close = Button(iconName: "window-close-symbolic")
        close.addCSSClass(.flat)
        close.tooltipText = "Hide Visualize (Ctrl+Alt+V)"
        close.setAccessibleLabel("Hide Visualize")
        close.onClicked { [weak self] in self?.hide() }

        let spacer = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        spacer.hexpand = true
        let header = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        header.addCSSClass("oneroot-operations-header")
        header.append(title)
        header.append(segments)
        header.append(spacer)
        header.append(spinner)
        header.append(stopButton)
        header.append(rescanButton)
        header.append(close)

        summaryLabel.xalign = 0
        summaryLabel.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        summaryLabel.addCSSClass(.dimLabel)
        summaryLabel.addCSSClass("caption")
        summaryLabel.marginStart = 12
        summaryLabel.marginEnd = 12
        summaryLabel.marginBottom = 4

        list.selectionMode = GTK_SELECTION_NONE
        scroller.child = list
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.widgetPointer), 220)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)

        widget.append(Separator(orientation: GTK_ORIENTATION_HORIZONTAL))
        widget.append(header)
        widget.append(summaryLabel)
        widget.append(scroller)

        darkConnection = StyleManager.default.onDarkChanged { [weak self] in self?.refresh() }
        let viewModel = self.viewModel
        watches.append(ObservationWatch.watch({
            (viewModel.report, viewModel.isScanning, viewModel.errorMessage, viewModel.breakdown, viewModel.selectedGroup)
        }) { [weak self] _ in self?.refresh() })
    }

    // MARK: Showing

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        widget.visible = true
        viewModel.show(folder, delay: .zero)
        refresh()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        widget.visible = false
        // Nothing is scanned with the panel hidden.
        viewModel.stop()
        viewModel.show(nil)
    }

    /// The active pane moved to `folder` (nil for a virtual location).
    func setFolder(_ folder: URL?) {
        self.folder = folder
        if isShown { viewModel.show(folder) }
    }

    // MARK: Refreshing

    private func refresh() {
        guard isShown else { return }
        isSyncing = true
        for (breakdown, button) in breakdownButtons where button.active != (breakdown == viewModel.breakdown) {
            button.active = breakdown == viewModel.breakdown
        }
        isSyncing = false
        spinner.visible = viewModel.isScanning
        stopButton.visible = viewModel.isScanning
        rescanButton.visible = !viewModel.isScanning
        rescanButton.sensitive = folder != nil

        list.removeAll()
        if let error = viewModel.errorMessage {
            summaryLabel.text = ""
            list.append(message(error))
        } else if let report = viewModel.report {
            summaryLabel.text = summary(report)
            switch viewModel.breakdown {
            case .folders: addFolderRows(report)
            default: addGroupRows(groups(report), report: report)
            }
        } else if viewModel.isScanning {
            summaryLabel.text = ""
            list.append(message("Scanning\u{2026}"))
        } else {
            summaryLabel.text = ""
            list.append(message("Open a folder to see what\u{2019}s taking up space in it."))
        }
    }

    private func message(_ text: String) -> Label {
        let label = Label(text)
        label.addCSSClass(.dimLabel)
        label.marginTop = 12
        label.marginBottom = 12
        return label
    }

    private func summary(_ report: StorageReport) -> String {
        var parts = [
            Formatting.size(report.totalSize),
            report.fileCount == 1 ? "1 file" : "\(report.fileCount) files",
            report.folderCount == 1 ? "1 folder" : "\(report.folderCount) folders",
        ]
        if report.unreadableCount > 0 { parts.append("\(report.unreadableCount) couldn\u{2019}t be read") }
        let name = report.root.path
        let prefix = viewModel.isScanning ? "Scanning \(name)\u{2026} so far " : "\(name): "
        return prefix + parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Folders

    private func addFolderRows(_ report: StorageReport) {
        guard !report.children.isEmpty else {
            list.append(message(report.isComplete ? "Nothing in this folder." : "Nothing counted yet."))
            return
        }
        let largest = max(report.children.first?.size ?? 0, 1)
        // The treemap beside the same items as bar rows.
        let rows = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        let treemap = TreemapView()
        treemap.set(TreemapBlocks.blocks(children: report.children, totalSize: report.totalSize), total: report.totalSize)
        treemap.onChoose = { [weak self] block in
            guard let entry = block.entry else { return }
            if entry.isDirectory { self?.onOpenFolder?(entry.url) } else { self?.onReveal?(entry.url) }
        }
        treemapView = treemap
        for entry in report.children {
            let row = barRow(
                icon: entry.isDirectory ? "folder-symbolic" : "text-x-generic-symbolic",
                title: entry.name,
                detail: entry.isDirectory ? "\(Formatting.size(entry.size)) \u{00B7} \(entry.fileCount) files" : Formatting.size(entry.size),
                fraction: Double(entry.size) / Double(largest),
                label: "\(entry.name), \(Formatting.size(entry.size))"
            )
            let url = entry.url
            let isDirectory = entry.isDirectory
            activate(row, tooltip: isDirectory ? "Open \(entry.name)" : "Show \(entry.name) in its folder") { [weak self] in
                if isDirectory { self?.onOpenFolder?(url) } else { self?.onReveal?(url) }
            }
            rows.append(row)
        }
        let rowsScroller = ScrolledWindow(child: rows)
        rowsScroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        rowsScroller.setSizeRequest(width: 330, height: 200)
        let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        content.marginStart = 12
        content.marginEnd = 6
        content.marginBottom = 6
        treemap.widget.setSizeRequest(width: 200, height: 200)
        content.append(treemap.widget)
        content.append(rowsScroller)
        let holder = ListBoxRow()
        holder.activatable = false
        holder.selectable = false
        holder.child = content
        list.append(holder)
    }

    // MARK: Groups

    private struct Group {
        let id: String
        let title: String
        let icon: String
        let bucket: StorageBucket
        let color: ChartPalette.Color
    }

    private func groups(_ report: StorageReport) -> [Group] {
        switch viewModel.breakdown {
        case .folders:
            return []
        case .types:
            return StorageCategory.allCases.enumerated().compactMap { index, category in
                guard let bucket = report.categories[category], bucket.count > 0 else { return nil }
                return Group(id: category.rawValue, title: category.title, icon: "folder-symbolic", bucket: bucket, color: ChartPalette.series(at: index))
            }
        case .age:
            let ordered: [StorageAge] = [.thisWeek, .thisMonth, .thisYear, .older]
            var result = ordered.enumerated().compactMap { index, age -> Group? in
                guard let bucket = report.ages[age], bucket.count > 0 else { return nil }
                return Group(id: "\(age)", title: age.title, icon: "document-open-recent-symbolic", bucket: bucket, color: .ordinal(step: index, of: ordered.count))
            }
            if let unknown = report.ages[.unknown], unknown.count > 0 {
                result.append(Group(id: "unknown", title: StorageAge.unknown.title, icon: "document-open-recent-symbolic", bucket: unknown, color: .neutral))
            }
            return result
        case .tags:
            // Tags have no colors on Linux: the biggest get the palette in order.
            var result = report.tags
                .sorted { $0.value.size != $1.value.size ? $0.value.size > $1.value.size : $0.key < $1.key }
                .enumerated()
                .map { index, pair in
                    Group(id: "tag:" + pair.key, title: pair.key, icon: "tag-symbolic", bucket: pair.value, color: ChartPalette.series(at: index))
                }
            if report.untagged.count > 0 {
                result.append(Group(id: "untagged", title: "No tags", icon: "tag-symbolic", bucket: report.untagged, color: .neutral))
            }
            return result
        case .cloud:
            guard report.hasCloudItems else { return [] }
            return StorageCloudState.allCases.enumerated().compactMap { index, state in
                guard let bucket = report.cloud[state], bucket.count > 0 else { return nil }
                return Group(id: "\(state)", title: state.title, icon: "folder-remote-symbolic", bucket: bucket,
                             color: state == .notInCloud ? .neutral : ChartPalette.series(at: index))
            }
        }
    }

    /// A stacked bar of the groups, the groups as a list (color, count, size,
    /// share) and the chosen group's largest files, as on the Mac.
    private func addGroupRows(_ groups: [Group], report: StorageReport) {
        guard !groups.isEmpty else {
            let text: String
            switch viewModel.breakdown {
            case .cloud: text = "Nothing here is synced by a cloud provider."
            case .tags: text = "No tagged files here."
            default: text = report.isComplete ? "No files here." : "Nothing counted yet."
            }
            list.append(message(text))
            return
        }
        let dark = StyleManager.default.dark
        let total = max(groups.reduce(0) { $0 + $1.bucket.size }, 1)
        // The chosen group, or the largest until one is chosen.
        let current = groups.first { $0.id == viewModel.selectedGroup } ?? groups.max { $0.bucket.size < $1.bucket.size }

        let bar = StackedBarView()
        bar.set(groups.map { group in
            StackedBarView.Segment(
                id: group.id, size: group.bucket.size, className: ChartPalette.className(group.color, dark: dark),
                tooltip: "\(group.title) \u{2014} \(Formatting.size(group.bucket.size)) (\(TreemapBlocks.percent(group.bucket.size, of: total)))")
        }, current: current?.id)
        bar.onChoose = { [weak self] id in self?.viewModel.selectedGroup = id }
        barView = bar

        let groupRows = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        for group in groups {
            let isCurrent = current?.id == group.id
            let swatch = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
            swatch.addCSSClass("oneroot-chart-swatch")
            swatch.addCSSClass(ChartPalette.className(group.color, dark: dark))
            swatch.valign = GTK_ALIGN_CENTER
            let icon = Image(iconName: group.icon)
            icon.pixelSize = 14
            let title = Label(group.title)
            title.xalign = 0
            title.hexpand = true
            title.ellipsize = PANGO_ELLIPSIZE_END
            let detail = Label("\(group.bucket.count == 1 ? "1 item" : "\(group.bucket.count) items") \u{00B7} \(Formatting.size(group.bucket.size)) \u{00B7} \(TreemapBlocks.percent(group.bucket.size, of: total))")
            detail.addCSSClass(.dimLabel)
            detail.addCSSClass("caption")
            let line = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            line.marginTop = 3
            line.marginBottom = 3
            line.append(swatch)
            line.append(icon)
            line.append(title)
            line.append(detail)
            let row = Button()
            row.child = line
            row.addCSSClass(.flat)
            if isCurrent { row.addCSSClass("oneroot-visualize-selected") }
            row.setAccessibleLabel("\(group.title), \(group.bucket.count) items, \(Formatting.size(group.bucket.size)), \(TreemapBlocks.percent(group.bucket.size, of: total))")
            row.tooltipText = "Show the largest files in \(group.title)"
            let id = group.id
            row.onClicked { [weak self] in self?.viewModel.selectedGroup = id }
            groupRows.append(row)
        }
        let groupScroller = ScrolledWindow(child: groupRows)
        groupScroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        groupScroller.hexpand = true
        groupScroller.setSizeRequest(width: 260, height: 170)

        let largest = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        if let current {
            let heading = Label("Largest in \(current.title)")
            heading.xalign = 0
            heading.addCSSClass("heading")
            heading.addCSSClass("caption")
            largest.append(heading)
            let fileRows = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
            for file in current.bucket.largest {
                let name = Label(file.url.lastPathComponent)
                name.xalign = 0
                name.hexpand = true
                name.ellipsize = PANGO_ELLIPSIZE_MIDDLE
                let path = Label(file.url.deletingLastPathComponent().path)
                path.xalign = 0
                path.ellipsize = PANGO_ELLIPSIZE_START
                path.addCSSClass(.dimLabel)
                path.addCSSClass("caption")
                let text = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
                text.hexpand = true
                text.append(name)
                text.append(path)
                let size = Label(Formatting.size(file.size))
                size.addCSSClass(.dimLabel)
                size.addCSSClass("caption")
                let line = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
                line.append(text)
                line.append(size)
                let row = Button()
                row.child = line
                row.addCSSClass(.flat)
                row.setAccessibleLabel("\(file.url.lastPathComponent), \(Formatting.size(file.size))")
                row.tooltipText = "Show \(file.url.lastPathComponent) in the list"
                let url = file.url
                row.onClicked { [weak self] in self?.onReveal?(url) }
                fileRows.append(row)
            }
            let fileScroller = ScrolledWindow(child: fileRows)
            fileScroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
            fileScroller.vexpand = true
            fileScroller.setSizeRequest(width: 260, height: 150)
            largest.append(fileScroller)
        }
        largest.hexpand = true

        let columns = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        columns.append(groupScroller)
        columns.append(largest)
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        content.marginStart = 12
        content.marginEnd = 12
        content.marginBottom = 6
        content.append(bar.widget)
        content.append(columns)
        let holder = ListBoxRow()
        holder.activatable = false
        holder.selectable = false
        holder.child = content
        list.append(holder)
    }

    // MARK: Rows

    private func barRow(icon: String, title: String, detail: String, fraction: Double, label: String) -> Button {
        let image = Image(iconName: icon)
        image.pixelSize = 16
        let name = Label(title)
        name.xalign = 0
        name.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        name.hexpand = true
        let size = Label(detail)
        size.xalign = 1
        size.addCSSClass(.dimLabel)
        size.addCSSClass("caption")
        let top = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        top.append(image)
        top.append(name)
        top.append(size)
        let bar = ProgressBar()
        bar.fraction = min(1, max(0, fraction))
        bar.setAccessibleLabel("Share of the largest: \(label)")
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 3)
        content.marginTop = 3
        content.marginBottom = 3
        content.append(top)
        content.append(bar)
        let row = Button()
        row.child = content
        row.addCSSClass(.flat)
        row.marginStart = 6
        row.marginEnd = 6
        row.setAccessibleLabel(label)
        return row
    }

    private func activate(_ row: Button, tooltip: String, _ action: @escaping @MainActor () -> Void) {
        row.tooltipText = tooltip
        row.onClicked(action)
    }
}
