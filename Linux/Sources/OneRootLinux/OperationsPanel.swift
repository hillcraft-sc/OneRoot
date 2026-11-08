import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The File Operations panel: copies, moves, compress and extract in flight
/// (with speed, time left, Pause, Cancel, Start Now) and the recent ones
/// (with Retry), over the shared `FileOperationProgressCenter` — the same
/// model the Mac's File Operations card shows. Sits above the status bar and
/// is hidden until there is something to show or the user opens it.
@MainActor
final class OperationsPanel {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)

    /// The panel shows or hides itself (an operation began, finished, or the
    /// user closed it).
    var onVisibilityChange: ((Bool) -> Void)?

    private let center: FileOperationProgressCenter
    private let list = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private let scroller = ScrolledWindow()
    private let emptyLabel = Label("No file operations yet")
    private let clearButton = Button(label: "Clear")
    private var activeRows: [UUID: ActiveRow] = [:]
    private var recordRows: [UUID: RecordRow] = [:]
    private var watches: [ObservationWatch] = []
    private var tickerRunning = false
    private var autoHideGeneration = 0
    /// Opened by the user (the status-bar button or Ctrl+Shift+O): stays
    /// until they close it, instead of hiding itself after a quiet success.
    private var pinnedOpen = false
    private(set) var isShown = false
    /// This panel's number for the center's "card showing" bookkeeping.
    private let windowNumber = Int.random(in: 1_000_000..<Int.max)

    private let verifyCheck = CheckButton(label: "Verify copies")
    private let queueCheck = CheckButton(label: "Copy to the same disk one at a time")

    init(center: FileOperationProgressCenter = .shared) {
        self.center = center
        widget.addCSSClass("oneroot-operations")
        widget.setAccessibleLabel("File Operations")
        widget.visible = false

        let title = Label("File Operations")
        title.addCSSClass("heading")
        title.xalign = 0
        title.hexpand = true

        clearButton.addCSSClass(.flat)
        clearButton.tooltipText = "Remove finished operations from the list"
        clearButton.setAccessibleLabel("Clear finished operations")
        clearButton.onClicked { [weak self] in self?.clearFinished() }

        let close = Button(iconName: "window-close-symbolic")
        close.addCSSClass(.flat)
        close.tooltipText = "Hide File Operations (Ctrl+Shift+O)"
        close.setAccessibleLabel("Hide File Operations")
        close.onClicked { [weak self] in self?.hide() }

        let header = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        header.addCSSClass("oneroot-operations-header")
        header.append(title)
        header.append(clearButton)
        header.append(close)

        emptyLabel.addCSSClass(.dimLabel)
        emptyLabel.marginTop = 10
        emptyLabel.marginBottom = 10
        list.append(emptyLabel)

        scroller.child = list
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.widgetPointer), 150)
        // The list grows with its rows up to a few, then scrolls (see `updateEmptyState`).
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)

        verifyCheck.active = UserDefaults.standard.bool(forKey: FileVerifier.enabledKey)
        verifyCheck.tooltipText = "Read each copy to another disk back and compare it with the original"
        verifyCheck.onToggled { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.verifyCheck.active, forKey: FileVerifier.enabledKey)
        }
        queueCheck.active = UserDefaults.standard.object(forKey: FileTransferQueue.enabledKey) as? Bool ?? true
        queueCheck.tooltipText = "Copies to the same disk wait their turn instead of slowing each other down"
        queueCheck.onToggled { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.queueCheck.active, forKey: FileTransferQueue.enabledKey)
        }
        let options = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 18)
        options.addCSSClass("oneroot-operations-options")
        options.append(verifyCheck)
        options.append(queueCheck)

        widget.append(Separator(orientation: GTK_ORIENTATION_HORIZONTAL))
        widget.append(header)
        widget.append(scroller)
        widget.append(options)

        watches.append(ObservationWatch.watch({ [center] in center.operations.map(\.id) }) { [weak self] _ in
            self?.operationsChanged()
        })
        // Any change to an operation (bytes, pause, waiting…) refreshes its row.
        watches.append(ObservationWatch.watch({ [center] in center.operations }, emitsInitialValue: false) { [weak self] _ in
            self?.refreshActiveRows()
        })
        watches.append(ObservationWatch.watch({ [center] in center.recent.map(\.id) }) { [weak self] _ in
            self?.recentChanged()
        })
    }

    // MARK: Showing

    /// How many failures finished since the panel was last open — for the
    /// status-bar badge.
    var unseenFailureCount: Int { center.unseenFailureCount }
    var activeCount: Int { center.operations.count }

    func toggle() {
        if isShown { hide() } else { show(pinned: true) }
    }

    func show(pinned: Bool = false) {
        if pinned { pinnedOpen = true }
        autoHideGeneration += 1
        guard !isShown else { return }
        isShown = true
        widget.visible = true
        center.setCardShowing(true, inWindow: windowNumber)
        verifyCheck.active = UserDefaults.standard.bool(forKey: FileVerifier.enabledKey)
        queueCheck.active = UserDefaults.standard.object(forKey: FileTransferQueue.enabledKey) as? Bool ?? true
        onVisibilityChange?(true)
    }

    func hide() {
        pinnedOpen = false
        autoHideGeneration += 1
        guard isShown else { return }
        isShown = false
        widget.visible = false
        center.setCardShowing(false, inWindow: windowNumber)
        onVisibilityChange?(false)
    }

    // MARK: Rows

    private func operationsChanged() {
        let operations = center.operations
        let ids = Set(operations.map(\.id))
        for (id, row) in activeRows where !ids.contains(id) {
            list.remove(row.widget)
            activeRows[id] = nil
        }
        for operation in operations where activeRows[operation.id] == nil {
            let row = ActiveRow(operation: operation, center: center)
            activeRows[operation.id] = row
            list.prepend(row.widget)
        }
        refreshActiveRows()
        updateEmptyState()
        if !operations.isEmpty {
            show()
            startTicker()
        } else {
            scheduleAutoHide()
        }
    }

    private func refreshActiveRows() {
        let now = Date()
        for operation in center.operations {
            activeRows[operation.id]?.update(operation, now: now)
        }
    }

    private func recentChanged() {
        let records = center.recent
        let ids = Set(records.map(\.id))
        for (id, row) in recordRows where !ids.contains(id) {
            list.remove(row.widget)
            recordRows[id] = nil
        }
        // `recent` is newest first; the list is active rows, then records.
        var previous: Widget? = activeRows.values.map(\.widget).last
        for record in records {
            if recordRows[record.id] == nil {
                let row = RecordRow(record: record, center: center)
                recordRows[record.id] = row
                if let previous {
                    list.insertChildAfter(row.widget, sibling: previous)
                } else {
                    list.prepend(row.widget)
                }
            }
            previous = recordRows[record.id]?.widget
        }
        updateEmptyState()
        if let newest = records.first, case .failed = newest.outcome, !isShown { show() }
    }

    private func updateEmptyState() {
        emptyLabel.visible = activeRows.isEmpty && recordRows.isEmpty
        clearButton.visible = !recordRows.isEmpty
    }

    private func clearFinished() {
        center.clearRecent(failures: false)
        center.clearRecent(failures: true)
    }

    /// A quiet success closes the panel after a few seconds; a failure or a
    /// panel the user opened stays until they close it.
    private func scheduleAutoHide() {
        guard !pinnedOpen else { return }
        if center.recent.contains(where: { $0.outcome.isFailure }) { return }
        autoHideGeneration += 1
        let generation = autoHideGeneration
        MainContext.delay(ms: 4000) { [weak self] in
            guard let self, generation == self.autoHideGeneration,
                  self.center.operations.isEmpty, !self.pinnedOpen else { return }
            self.hide()
        }
    }

    // MARK: Ticker (elapsed time and the pulse of unsized operations)

    private func startTicker() {
        guard !tickerRunning else { return }
        tickerRunning = true
        tick()
    }

    private func tick() {
        MainContext.delay(ms: 500) { [weak self] in
            guard let self else { return }
            guard !self.center.operations.isEmpty else {
                self.tickerRunning = false
                return
            }
            self.refreshActiveRows()
            self.tick()
        }
    }
}

// MARK: - Active row

@MainActor
private final class ActiveRow {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 4)
    private let id: UUID
    private unowned let center: FileOperationProgressCenter
    private let title = Label("")
    private let item = Label("")
    private let status = Label("")
    private let bar = ProgressBar()
    private let pauseButton = Button(iconName: "media-playback-pause-symbolic")
    private let startNowButton = Button(label: "Start Now")
    private let cancelButton = Button(iconName: "process-stop-symbolic")

    init(operation: FileOperationProgress, center: FileOperationProgressCenter) {
        id = operation.id
        self.center = center
        widget.addCSSClass("oneroot-operation-row")
        widget.setAccessibleLabel(operation.title)

        title.xalign = 0
        title.hexpand = true
        title.ellipsize = PANGO_ELLIPSIZE_END
        title.addCSSClass("heading")
        item.xalign = 0
        item.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        status.xalign = 0
        status.ellipsize = PANGO_ELLIPSIZE_END
        for label in [item, status] {
            label.addCSSClass(.dimLabel)
            label.addCSSClass("caption")
        }

        startNowButton.addCSSClass(.flat)
        startNowButton.tooltipText = "Don't wait: copy now, even though another copy is using this disk"
        startNowButton.onClicked { [weak self] in
            guard let self else { return }
            self.center.requestStartNow(self.id)
        }
        pauseButton.addCSSClass(.flat)
        pauseButton.onClicked { [weak self] in
            guard let self, let current = self.center.operations.first(where: { $0.id == self.id }) else { return }
            if current.isPaused { self.center.requestResume(self.id) } else { self.center.requestPause(self.id) }
        }
        cancelButton.addCSSClass(.flat)
        cancelButton.tooltipText = "Cancel"
        cancelButton.setAccessibleLabel("Cancel \(operation.title)")
        cancelButton.onClicked { [weak self] in
            guard let self else { return }
            self.center.requestCancel(self.id)
        }
        bar.hexpand = true
        bar.valign = GTK_ALIGN_CENTER
        bar.setAccessibleLabel("Progress of \(operation.title)")

        let top = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        top.append(title)
        top.append(startNowButton)
        top.append(pauseButton)
        top.append(cancelButton)
        widget.append(top)
        widget.append(item)
        widget.append(bar)
        widget.append(status)
        update(operation, now: Date())
    }

    func update(_ operation: FileOperationProgress, now: Date) {
        title.text = operation.title
        let current = FileOperationText.currentItem(for: operation)
        item.text = current ?? ""
        item.visible = current != nil
        status.text = operation.isCancelling ? "Cancelling\u{2026}" : FileOperationText.status(for: operation, now: now)

        let indeterminate = operation.isIndeterminate || operation.isPreparing || operation.isWaiting || operation.totalBytes <= 0
        if indeterminate {
            if !operation.isPaused && !operation.isWaiting { bar.pulse() }
        } else {
            bar.fraction = min(1, max(0, Double(operation.completedBytes) / Double(operation.totalBytes)))
        }
        startNowButton.visible = operation.isWaiting && operation.startNow != nil
        pauseButton.visible = operation.pauseControl != nil
        pauseButton.sensitive = operation.canPause
        pauseButton.iconName = operation.isPaused ? "media-playback-start-symbolic" : "media-playback-pause-symbolic"
        pauseButton.tooltipText = operation.isPaused ? "Resume" : "Pause"
        pauseButton.setAccessibleLabel((operation.isPaused ? "Resume " : "Pause ") + operation.title)
        cancelButton.sensitive = !operation.isCancelling
    }
}

// MARK: - Finished row

@MainActor
private final class RecordRow {
    let widget = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)

    init(record: FileOperationRecord, center: FileOperationProgressCenter) {
        widget.addCSSClass("oneroot-operation-row")
        let icon = Image(iconName: Self.iconName(record.outcome))
        icon.valign = GTK_ALIGN_START
        if record.outcome.isFailure { icon.addCSSClass(.error) }

        let text = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        text.hexpand = true
        let title = Label(record.title)
        title.xalign = 0
        title.ellipsize = PANGO_ELLIPSIZE_END
        let summary = Label(FileOperationText.summary(for: record))
        summary.xalign = 0
        summary.addCSSClass(.dimLabel)
        summary.addCSSClass("caption")
        text.append(title)
        text.append(summary)
        if case .failed(let message, let detail) = record.outcome {
            let reason = Label([message, detail].compactMap { $0 }.joined(separator: "\n"))
            reason.xalign = 0
            reason.wrap = true
            reason.selectable = true
            reason.addCSSClass("caption")
            reason.addCSSClass(.error)
            text.append(reason)
        }
        widget.append(icon)
        widget.append(text)

        if record.retry != nil {
            let retry = Button(label: "Retry")
            retry.valign = GTK_ALIGN_START
            retry.tooltipText = "Run it again for what didn't finish"
            retry.setAccessibleLabel("Retry \(record.title)")
            let id = record.id
            retry.onClicked { [weak center] in center?.retry(id) }
            widget.append(retry)
        }
        let remove = Button(iconName: "window-close-symbolic")
        remove.addCSSClass(.flat)
        remove.valign = GTK_ALIGN_START
        remove.tooltipText = "Remove from the list"
        remove.setAccessibleLabel("Remove \(record.title) from the list")
        let id = record.id
        remove.onClicked { [weak center] in center?.removeRecord(id) }
        widget.append(remove)
        widget.setAccessibleLabel("\(record.title): \(FileOperationText.summary(for: record))")
    }

    private static func iconName(_ outcome: FileOperationOutcome) -> String {
        switch outcome {
        case .succeeded: return "object-select-symbolic"
        case .cancelled: return "process-stop-symbolic"
        case .failed: return "dialog-warning-symbolic"
        }
    }
}
