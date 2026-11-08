import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Show All History: every folder visited (`NavigationHistoryStore`, newest
/// first, up to the cap in Settings) with a filter box. Double-click or
/// Enter opens the folder in the active window. One instance on `OneRootApp`.
@MainActor
final class HistoryWindow {
    let window: ApplicationWindow
    var onClose: (() -> Void)?
    /// Open `url` in the window the user was last in.
    var onOpen: ((URL) -> Void)?

    private let history = NavigationHistoryStore.shared
    private let filter = SearchEntry()
    private let list = ListBox()
    private let countLabel = Label("")
    private let emptyLabel = Label("")
    private let openButton = Button(label: "Open")
    private let clearButton = Button(label: "Clear History")
    private var shown: [URL] = []
    private var watch: ObservationWatch?

    init(application: Application) {
        window = ApplicationWindow(application: application)
        window.title = "History"
        window.defaultWidth = 560
        window.defaultHeight = 440
        buildLayout()
        wire()
        reload()
    }

    func present() {
        window.present()
        _ = filter.grabFocus()
    }

    /// The entries whose path contains `query` (any case); all of them when
    /// the query is empty.
    nonisolated static func matching(_ entries: [URL], query: String) -> [URL] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.path.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: Layout

    private func buildLayout() {
        filter.placeholderText = "Filter"
        filter.setAccessibleLabel("Filter history")
        filter.marginStart = 8
        filter.marginEnd = 8
        filter.marginTop = 8
        filter.marginBottom = 8

        list.addCSSClass("navigation-sidebar")
        list.setAccessibleLabel("History")
        let scroller = ScrolledWindow(child: list)
        scroller.vexpand = true
        emptyLabel.addCSSClass(.dimLabel)
        emptyLabel.vexpand = true
        emptyLabel.visible = false
        countLabel.addCSSClass(.dimLabel)
        countLabel.hexpand = true
        countLabel.xalign = 0

        let buttons = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        buttons.marginStart = 8
        buttons.marginEnd = 8
        buttons.marginTop = 8
        buttons.marginBottom = 8
        buttons.append(countLabel)
        buttons.append(clearButton)
        buttons.append(openButton)
        openButton.addCSSClass("suggested-action")

        let body = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        body.append(filter)
        body.append(scroller)
        body.append(emptyLabel)
        body.append(buttons)

        let toolbar = ToolbarView()
        toolbar.addTopBar(HeaderBar())
        toolbar.setContent(body)
        window.setContent(toolbar)
    }

    private func wire() {
        filter.onSearchChanged { [weak self] in self?.reload() }
        list.onRowActivated { [weak self] row in self?.open(at: row.index) }
        list.onRowSelected { [weak self] _ in self?.updateButtons() }
        openButton.onClicked { [weak self] in
            guard let self, let row = self.list.selectedRow else { return }
            self.open(at: row.index)
        }
        clearButton.onClicked { [weak self] in self?.history.clear() }
        watch = ObservationWatch.watch({ NavigationHistoryStore.shared.entries }, emitsInitialValue: false) { [weak self] _ in
            self?.reload()
        }
        window.onCloseRequest { [weak self] in
            self?.onClose?()
            return false
        }
        let keys = EventControllerKey()
        keys.onKeyPressed { [weak self] keyval, _, _ in
            guard keyval == UInt32(GDK_KEY_Escape) else { return false }
            self?.window.close()
            return true
        }
        window.addController(keys)

        // From the filter field: Up/Down move through the list, Enter opens.
        let fieldKeys = EventControllerKey()
        fieldKeys.onKeyPressed { [weak self] keyval, _, _ in
            guard let self else { return false }
            let current = self.list.selectedRow?.index ?? 0
            switch keyval {
            case UInt32(GDK_KEY_Down):
                if current + 1 < self.shown.count { self.list.selectRow(at: current + 1) }
                return true
            case UInt32(GDK_KEY_Up):
                if current > 0 { self.list.selectRow(at: current - 1) }
                return true
            case UInt32(GDK_KEY_Return), UInt32(GDK_KEY_KP_Enter):
                self.open(at: current)
                return true
            default:
                return false
            }
        }
        gtk_event_controller_set_propagation_phase(OpaquePointer(fieldKeys.pointer), GTK_PHASE_CAPTURE)
        filter.addController(fieldKeys)
    }

    // MARK: Rows

    private func reload() {
        shown = Self.matching(history.entries, query: filter.text)
        list.removeAll()
        for url in shown { list.append(makeRow(url)) }
        let total = history.entries.count
        countLabel.text = total == 1 ? "1 location" : "\(total) locations"
        emptyLabel.text = total == 0 ? "No history yet." : "No matches."
        emptyLabel.visible = shown.isEmpty
        list.visible = !shown.isEmpty
        clearButton.sensitive = total > 0
        if !shown.isEmpty { list.selectRow(at: 0) }
        updateButtons()
    }

    private func updateButtons() {
        openButton.sensitive = list.selectedRow != nil
    }

    private func makeRow(_ url: URL) -> ListBoxRow {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 1)
        box.marginStart = 8
        box.marginEnd = 8
        box.marginTop = 4
        box.marginBottom = 4
        let name = Label(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        name.xalign = 0
        name.ellipsize = PANGO_ELLIPSIZE_END
        let path = Label(url.deletingLastPathComponent().path)
        path.xalign = 0
        path.ellipsize = PANGO_ELLIPSIZE_START
        path.addCSSClass(.dimLabel)
        path.addCSSClass("caption")
        box.append(name)
        box.append(path)
        let row = ListBoxRow()
        row.child = box
        row.setAccessibleLabel(url.path)
        return row
    }

    private func open(at index: Int) {
        guard index >= 0, index < shown.count else { return }
        onOpen?(shown[index])
    }
}
