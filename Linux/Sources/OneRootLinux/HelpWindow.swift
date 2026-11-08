import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Help window (F1): topics on the left with a search field, the
/// selected topic on the right. Topics come from `LinuxHelpContent`; search
/// is the shared `HelpSearch`. One instance on `OneRootApp`.
@MainActor
final class HelpWindow {
    let window: ApplicationWindow
    var onClose: (() -> Void)?

    private let search = SearchEntry()
    private let list = ListBox()
    private let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
    private let scroller = ScrolledWindow()
    private var shownIDs: [HelpTopicID] = []
    private var snippets: [HelpTopicID: String] = [:]

    init(application: Application) {
        window = ApplicationWindow(application: application)
        window.title = "OneRoot Help"
        window.defaultWidth = 900
        window.defaultHeight = 640
        buildLayout()
        wire()
        showTopics(matching: "")
        show(.gettingStarted)
    }

    func present(topic: HelpTopicID? = nil) {
        if let topic {
            search.text = ""
            showTopics(matching: "")
            show(topic)
        }
        window.present()
    }

    // MARK: Layout

    private func buildLayout() {
        search.placeholderText = "Search Help"
        search.setAccessibleLabel("Search Help")
        search.marginStart = 8
        search.marginEnd = 8
        search.marginTop = 8
        search.marginBottom = 8

        list.addCSSClass("navigation-sidebar")
        let listScroller = ScrolledWindow(child: list)
        listScroller.vexpand = true
        let side = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        side.setSizeRequest(width: 260)
        side.append(search)
        side.append(listScroller)

        content.marginStart = 28
        content.marginEnd = 28
        content.marginTop = 20
        content.marginBottom = 28
        scroller.child = content
        gtk_scrolled_window_set_policy(scroller.opaquePointer, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        scroller.hexpand = true
        scroller.vexpand = true

        let split = Paned(orientation: GTK_ORIENTATION_HORIZONTAL, start: side, end: scroller)
        split.position = 270
        split.shrinkStartChild = false
        split.resizeStartChild = false

        let toolbar = ToolbarView()
        toolbar.addTopBar(HeaderBar())
        toolbar.setContent(split)
        window.setContent(toolbar)
    }

    private func wire() {
        search.onSearchChanged { [weak self] in
            guard let self else { return }
            self.showTopics(matching: self.search.text)
        }
        list.onRowSelected { [weak self] row in
            guard let self, let row, let id = self.shownIDs[safe: row.index] else { return }
            self.render(id)
        }
        window.onCloseRequest { [weak self] in
            self?.onClose?()
            return false
        }
    }

    // MARK: Topic list

    private func showTopics(matching query: String) {
        let topics = LinuxHelpContent.topics
        var ids: [HelpTopicID]
        snippets = [:]
        if HelpSearch.terms(in: query).isEmpty {
            ids = topics.map(\.id)
        } else {
            let results = HelpSearch.results(for: query, in: topics)
            ids = results.map(\.topicID)
            for result in results { if let snippet = result.snippet { snippets[result.topicID] = snippet } }
        }
        shownIDs = ids
        while let child = list.firstChild { list.remove(child) }
        if ids.isEmpty {
            let none = Label("No topics match \u{201C}\(query)\u{201D}")
            none.addCSSClass(.dimLabel)
            none.marginStart = 12
            none.marginTop = 12
            let row = ListBoxRow()
            row.child = none
            row.selectable = false
            row.activatable = false
            list.append(row)
            return
        }
        for id in ids {
            guard let topic = LinuxHelpContent.topic(id) else { continue }
            let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
            let title = Label(topic.title)
            title.xalign = 0
            box.append(title)
            if let snippet = snippets[id] {
                let detail = Label(snippet)
                detail.xalign = 0
                detail.ellipsize = PANGO_ELLIPSIZE_END
                detail.addCSSClass(.dimLabel)
                detail.addCSSClass("caption")
                box.append(detail)
            }
            box.marginStart = 6
            box.marginEnd = 6
            box.marginTop = 6
            box.marginBottom = 6
            let row = ListBoxRow()
            row.child = box
            list.append(row)
        }
        list.selectRow(at: 0)
    }

    func show(_ id: HelpTopicID) {
        if let index = shownIDs.firstIndex(of: id) { list.selectRow(at: index) }
        render(id)
    }

    // MARK: Topic body

    private func render(_ id: HelpTopicID) {
        guard let topic = LinuxHelpContent.topic(id) else { return }
        while let child = content.firstChild { content.remove(child) }
        let title = Label(topic.title)
        title.xalign = 0
        title.addCSSClass("title-1")
        title.setAccessibleLabel(topic.title)
        content.append(title)
        for block in topic.blocks { content.append(view(for: block)) }
        let related = topic.seeAlso.compactMap { LinuxHelpContent.topic($0) }
        if !related.isEmpty {
            let heading = Label("See also")
            heading.xalign = 0
            heading.addCSSClass("heading")
            heading.marginTop = 10
            content.append(heading)
            let row = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
            for other in related {
                let button = Button(label: other.title)
                button.addCSSClass(.flat)
                button.halign = GTK_ALIGN_START
                let target = other.id
                button.onClicked { [weak self] in
                    self?.search.text = ""
                    self?.showTopics(matching: "")
                    self?.show(target)
                }
                row.append(button)
            }
            content.append(row)
        }
        scroller.verticalAdjustment.value = 0
    }

    private func text(_ markup: String) -> Label {
        let label = Label("")
        label.markup = HelpMarkup.pango(markup)
        label.xalign = 0
        label.wrap = true
        label.widthChars = 20
        label.maxWidthChars = 80
        label.selectable = true
        return label
    }

    private func plain(_ value: String) -> Label {
        let label = Label(value)
        label.xalign = 0
        label.wrap = true
        label.widthChars = 12
        label.maxWidthChars = 80
        label.selectable = true
        return label
    }

    private func view(for block: HelpBlock) -> Widget {
        switch block {
        case .heading(let value):
            let label = Label(value)
            label.xalign = 0
            label.addCSSClass("title-4")
            label.marginTop = 8
            return label
        case .paragraph(let value):
            return text(value)
        case .bullets(let items):
            let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
            for item in items {
                let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
                let bullet = Label("\u{2022}")
                bullet.yalign = 0
                row.append(bullet)
                let body = text(item)
                body.hexpand = true
                row.append(body)
                box.append(row)
            }
            return box
        case .shortcuts(let rows), .terms(let rows):
            let grid = Grid()
            grid.columnSpacing = 18
            grid.rowSpacing = 6
            var isShortcuts = false
            if case .shortcuts = block { isShortcuts = true }
            for (index, (left, right)) in rows.enumerated() {
                let key = plain(left)
                key.yalign = 0
                if isShortcuts { key.addCSSClass("monospace") }
                let detail = isShortcuts ? plain(right) : text(right)
                detail.hexpand = true
                grid.attach(key, column: 0, row: index)
                grid.attach(detail, column: 1, row: index)
            }
            return grid
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
