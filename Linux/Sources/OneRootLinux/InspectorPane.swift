import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Inspector: a preview and the properties of what's selected in the
/// focused pane — the Mac Inspector's Preview and Details, over what Linux
/// can read reliably (see `ItemInfo`). Empty selection shows the current
/// folder; several items show a count and total size.
///
/// Reading is cancelled when the selection changes and a stale answer is
/// dropped (`generation`), so rapidly moving through a list never lets an
/// old item overwrite the current one.
@MainActor
final class InspectorPane {
    private enum Content {
        case folder(URL?, items: Int, folders: Int)
        case multiple(count: Int, bytes: Int64, folders: Int)
        case loading(FileNode)
        case item(FileNode, ItemInfo)
        case unreadable(FileNode, String)
    }

    let widget: Box
    /// A button asked for a window action by name (`open`, `copy-path`, …).
    var onAction: ((String) -> Void)?

    private let body = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
    private var pane: FileListViewModel?
    private var paneWatch: ObservationWatch?
    private var task: Task<Void, Never>?
    private var generation = 0
    /// Which group of properties shows; kept while the selection changes.
    private var section: Section = .details
    private var shownContent: Content?
    private var tagTask: Task<Void, Never>?
    /// The Inspector redraws when the list reloads after a tag change; the
    /// add-a-tag field takes focus back so several tags can be typed in a row.
    private var refocusTagField = false

    private enum Section: String, CaseIterable {
        case details = "Details", moreInfo = "More Info", permissions = "Permissions"
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "tif", "tiff", "ico", "avif"]
    /// Images are decoded (scaled down) off the main thread; files past this
    /// size aren't previewed at all.
    private static let imageSizeLimit: Int64 = 200 * 1024 * 1024
    private static let previewPixels = 800
    /// The decoded preview of the item being shown.
    private var decodedImage: DecodedImage?

    init() {
        body.marginStart = 14
        body.marginEnd = 14
        body.marginTop = 14
        body.marginBottom = 14

        let scroller = ScrolledWindow(child: body)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.vexpand = true

        widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        widget.append(scroller)
        widget.setSizeRequest(width: 220)
        widget.setAccessibleLabel("Inspector")
    }

    // MARK: Binding

    /// Follows `pane`'s selection (or its folder, when nothing is selected).
    func bind(to pane: FileListViewModel) {
        self.pane = pane
        paneWatch = ObservationWatch.watch({
            (pane.selectedNodes.map(\.url), pane.currentDirectory, pane.items.count, pane.isPermissionDenied, pane.listingErrorMessage, pane.isLoading)
        }) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Stops following (the Inspector is hidden): no reads while it's closed.
    func unbind() {
        paneWatch = nil
        pane = nil
        task?.cancel()
        generation += 1
    }

    // MARK: Loading

    func refresh() {
        guard let pane else { return }
        task?.cancel()
        generation += 1
        let token = generation
        let nodes = pane.selectedNodes

        switch nodes.count {
        case 0:
            render(.folder(pane.currentDirectory, items: pane.items.count, folders: pane.items.filter(\.isDirectory).count))
        case 1:
            let node = nodes[0]
            render(.loading(node))
            let isDirectory = node.isDirectory
            let url = node.url
            let wantsText = !isDirectory && !Self.hasPagePreview(node) && (node.size ?? 0) > 0
            let wantsImage = Self.hasPagePreview(node) && (node.size ?? 0) <= Self.imageSizeLimit
            decodedImage = nil
            task = Task { [weak self] in
                let (result, image): (Result<ItemInfo, ItemInfo.ReadError>, DecodedImage?) = await Task.detached(priority: .userInitiated) {
                    do {
                        let info = try ItemInfo.read(url, isDirectory: isDirectory, wantsText: wantsText,
                                                 textBytes: Self.isMarkdown(url) ? 64 * 1024 : ItemInfo.previewBytes)
                        let image = wantsImage && !Task.isCancelled ? Self.decodePreview(url, maxSize: Self.previewPixels) : nil
                        return (.success(info), image)
                    } catch let error as ItemInfo.ReadError {
                        return (.failure(error), nil)
                    } catch {
                        return (.failure(.other(error.localizedDescription)), nil)
                    }
                }.value
                guard let self, !Task.isCancelled, token == self.generation else { return }
                self.decodedImage = image
                switch result {
                case .success(let info): self.render(.item(node, info))
                case .failure(.permissionDenied): self.render(.unreadable(node, "You don't have permission to see this item."))
                case .failure(.notFound): self.render(.unreadable(node, "This item no longer exists."))
                case .failure(.other(let message)): self.render(.unreadable(node, message))
                }
            }
        default:
            let files = nodes.filter { !$0.isDirectory }
            render(.multiple(count: nodes.count, bytes: files.compactMap(\.size).reduce(0, +), folders: nodes.count - files.count))
        }
    }

    // MARK: Rendering

    private func render(_ content: Content) {
        shownContent = content
        while let child = body.firstChild { body.remove(child) }
        switch content {
        case .folder(let url, let items, let folders):
            body.append(icon(named: "folder-symbolic", size: 64))
            body.append(title(url.map { AppWindow.title(for: $0) } ?? "Nothing selected"))
            if url != nil {
                if pane?.isPermissionDenied == true {
                    body.append(subtitle("You don't have permission to see what's in this folder."))
                } else if pane?.listingErrorMessage != nil {
                    body.append(subtitle("This folder can't be read."))
                } else {
                    body.append(subtitle(Formatting.summary(items: items, folders: folders, selected: 0)))
                }
                body.append(properties([("Location", url?.path)]))
            }
        case .multiple(let count, let bytes, let folders):
            body.append(icon(named: "edit-select-all-symbolic", size: 64))
            body.append(title("\(count) items selected"))
            var parts: [String] = []
            if folders > 0 { parts.append("\(folders) \(folders == 1 ? "folder" : "folders")") }
            if count - folders > 0 { parts.append("\(count - folders) \(count - folders == 1 ? "file" : "files"), \(Formatting.size(bytes))") }
            body.append(subtitle(parts.joined(separator: " · ")))
            body.append(actions(["copy-path": "Copy Paths"], order: ["copy-path"]))
        case .loading(let node):
            body.append(icon(for: node))
            body.append(title(node.name))
            let spinner = Label("Loading…")
            spinner.addCSSClass(.dimLabel)
            body.append(spinner)
        case .unreadable(let node, let message):
            body.append(icon(for: node))
            body.append(title(node.name))
            let label = Label(message)
            label.wrap = true
            label.addCSSClass(.dimLabel)
            body.append(label)
            body.append(properties([("Location", node.url.deletingLastPathComponent().path)]))
        case .item(let node, let info):
            if let preview = preview(for: node, info: info) { body.append(preview) } else { body.append(icon(for: node)) }
            body.append(title(node.name))
            var sub = [node.kind].compactMap { $0 }
            if node.isDirectory, let count = info.itemCount {
                sub.append("\(count) \(count == 1 ? "item" : "items")")
            } else if let size = info.size {
                sub.append(Formatting.size(size))
            }
            body.append(subtitle(sub.joined(separator: " · ")))
            var buttons = ["open": "Open", "copy-path": "Copy Path"]
            var order = ["open", "copy-path"]
            if node.isDirectory {
                buttons["open-new-tab"] = "Open in New Tab"
                buttons["pin"] = PinnedLocationsStore.shared.isPinned(node.url) ? "Unpin" : "Pin"
                order = ["open", "open-new-tab", "pin", "copy-path"]
            } else {
                buttons["open-with"] = "Open With…"
                order = ["open", "open-with", "copy-path"]
            }
            body.append(actions(buttons, order: order))
            body.append(sectionSwitcher())
            body.append(properties(rows(for: node, info: info, section: section)))
            if section == .details { body.append(tagEditor(for: node)) }
        }
    }

    private func rows(for node: FileNode, info: ItemInfo, section: Section) -> [(String, String?)] {
        switch section {
        case .details:
            return [
                ("Kind", node.kind),
                ("Size", node.isDirectory ? nil : info.size.map { $0 < 1000 ? Formatting.size($0) : "\(Formatting.size($0)) (\($0) bytes)" }),
                ("Items", info.itemCount.map(String.init)),
                ("Location", node.url.deletingLastPathComponent().path),
                ("Created", info.created.map { Formatting.date($0) }),
                ("Modified", info.modified.map { Formatting.date($0) }),
            ]
        case .moreInfo:
            return [
                ("On disk", node.isDirectory ? nil : info.sizeOnDisk.map(Formatting.size)),
                ("Links to", info.linkDestination),
                ("Accessed", info.accessed.map { Formatting.date($0) }),
            ]
        case .permissions:
            return [
                ("Owner", info.owner),
                ("Group", info.group),
                ("Permissions", info.permissions.map(ItemInfo.permissionText)),
            ]
        }
    }

    /// Details / More Info / Permissions, as linked toggle buttons.
    private func sectionSwitcher() -> Widget {
        let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        row.addCSSClass(.linked)
        row.halign = GTK_ALIGN_CENTER
        for candidate in Section.allCases {
            let button = ToggleButton()
            button.child = Label(candidate.rawValue)
            button.active = candidate == section
            button.setAccessibleLabel("\(candidate.rawValue) properties")
            button.onToggled { [weak self, weak button] in
                guard let self, let button, button.active, self.section != candidate else {
                    // Clicking the active one must not leave it off.
                    if let button, !button.active, self?.section == candidate { button.active = true }
                    return
                }
                self.section = candidate
                if let content = self.shownContent { self.render(content) }
            }
            row.append(button)
        }
        return row
    }

    /// Tag chips with a remove button each, and a field to add one. Tags are
    /// written (`user.xdg.tags`) off the main thread; a failure is shown, and
    /// the chips return to what is really on disk.
    private func tagEditor(for node: FileNode) -> Widget {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        box.marginTop = 6
        let heading = Label("Tags")
        heading.xalign = 0
        heading.addCSSClass(.dimLabel)
        heading.addCSSClass("caption")
        box.append(heading)

        let chips = FlowBox()
        chips.selectionMode = GTK_SELECTION_NONE
        chips.maxChildrenPerLine = 3
        box.append(chips)
        let status = Label("")
        status.xalign = 0
        status.wrap = true
        status.addCSSClass(.dimLabel)
        status.addCSSClass("caption")

        var tags = node.tags
        let url = node.url
        func reload() {
            while let child = chips.firstChild { chips.remove(child) }
            for tag in tags {
                let chip = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
                chip.addCSSClass(.linked)
                chip.append(Label(tag))
                let remove = Button(iconName: "window-close-symbolic")
                remove.addCSSClass(.flat)
                remove.setAccessibleLabel("Remove tag \(tag)")
                remove.onClicked { save(TagService.removing(tag, from: tags)) }
                chip.append(remove)
                chips.append(chip)
            }
        }
        func save(_ updated: [String]) {
            let previous = tags
            tags = updated
            reload()
            status.text = ""
            tagTask?.cancel()
            tagTask = Task { [weak self] in
                let error: String? = await Task.detached {
                    do { try TagService().setTags(updated, on: url); return nil } catch { return error.localizedDescription }
                }.value
                guard let error else { return }
                guard self != nil else { return }
                tags = previous
                reload()
                status.text = "Couldn't change tags: \(error)"
            }
        }
        reload()

        let field = Entry()
        field.placeholderText = "Add a tag\u{2026}"
        field.setAccessibleLabel("Add a tag")
        field.onActivate { [weak self, weak field] in
            guard let self, let field else { return }
            let updated = TagService.adding(field.text, to: tags)
            field.text = ""
            if updated != tags {
                self.refocusTagField = true
                save(updated)
            }
        }
        if refocusTagField {
            refocusTagField = false
            MainContext.task { _ = field.grabFocus() }
        }
        box.append(field)
        box.append(status)
        return box
    }

    // MARK: Pieces

    static func isImage(_ node: FileNode) -> Bool {
        !node.isDirectory && imageExtensions.contains(node.url.pathExtension.lowercased())
    }

    /// An image, or a PDF (its first page).
    static func hasPagePreview(_ node: FileNode) -> Bool {
        isImage(node) || (!node.isDirectory && PDFPagePreview.isPDF(node.url))
    }

    nonisolated static func decodePreview(_ url: URL, maxSize: Int) -> DecodedImage? {
        PDFPagePreview.isPDF(url)
            ? PDFPagePreview.firstPage(of: url, maxSize: maxSize)
            : DecodedImage.decode(path: url.path, maxSize: maxSize)
    }

    private func preview(for node: FileNode, info: ItemInfo) -> Widget? {
        if Self.hasPagePreview(node), let texture = decodedImage?.makeTexture() {
            let picture = Picture()
            picture.setPaintable(texture)
            picture.canShrink = true
            picture.contentFit = GTK_CONTENT_FIT_CONTAIN
            picture.setSizeRequest(width: -1, height: 200)
            picture.setAccessibleLabel("Preview of \(node.name)")
            return picture
        }
        if Self.isMarkdown(node.url), let text = info.textPreview {
            return markdownPreview(text, name: node.name)
        }
        if let text = info.textPreview {
            let label = Label(String(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(14).joined(separator: "\n")))
            label.xalign = 0
            label.yalign = 0
            label.wrap = true
            label.ellipsize = PANGO_ELLIPSIZE_END
            label.lines = 14
            label.selectable = true
            label.addCSSClass("monospace")
            label.addCSSClass("caption")
            label.setAccessibleLabel("Text preview of \(node.name)")
            let frame = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
            frame.addCSSClass("card")
            label.marginStart = 8
            label.marginEnd = 8
            label.marginTop = 8
            label.marginBottom = 8
            frame.append(label)
            return frame
        }
        return nil
    }

    static let showsRenderedMarkdownKey = "com.oneroot.inspector.showsRenderedMarkdown"

    nonisolated static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased())
    }

    /// A Markdown file: the raw text or as it reads (remembered, raw first,
    /// as on the Mac).
    private func markdownPreview(_ text: String, name: String) -> Widget {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        let switcher = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        switcher.addCSSClass(.linked)
        switcher.halign = GTK_ALIGN_CENTER
        let raw = ToggleButton(label: "Text")
        let rendered = ToggleButton(label: "Rendered")
        rendered.setGroup(raw)
        raw.setAccessibleLabel("Show the Markdown text")
        rendered.setAccessibleLabel("Show the Markdown rendered")
        switcher.append(raw)
        switcher.append(rendered)

        let content = Label("")
        content.xalign = 0
        content.yalign = 0
        content.wrap = true
        content.selectable = true
        content.marginStart = 8
        content.marginEnd = 8
        content.marginTop = 8
        content.marginBottom = 8
        let scroller = ScrolledWindow(child: content)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.setSizeRequest(width: -1, height: 220)
        let card = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        card.addCSSClass("card")
        card.append(scroller)

        func show(rendered isRendered: Bool) {
            if isRendered {
                content.removeCSSClass("monospace")
                content.markup = MarkdownPango.markup(from: text)
                content.setAccessibleLabel("Rendered Markdown of \(name)")
            } else {
                content.addCSSClass("monospace")
                content.text = text
                content.setAccessibleLabel("Markdown text of \(name)")
            }
        }
        let wantsRendered = UserDefaults.standard.bool(forKey: Self.showsRenderedMarkdownKey)
        rendered.active = wantsRendered
        raw.active = !wantsRendered
        show(rendered: wantsRendered)
        rendered.onToggled {
            guard rendered.active else { return }
            UserDefaults.standard.set(true, forKey: Self.showsRenderedMarkdownKey)
            show(rendered: true)
        }
        raw.onToggled {
            guard raw.active else { return }
            UserDefaults.standard.set(false, forKey: Self.showsRenderedMarkdownKey)
            show(rendered: false)
        }
        box.append(switcher)
        box.append(card)
        return box
    }

    private func icon(for node: FileNode) -> Image {
        let image = Image()
        image.pixelSize = 64
        FileIcons.set(image, to: node)
        return image
    }

    private func icon(named name: String, size: Int) -> Image {
        let image = Image(iconName: name)
        image.pixelSize = size
        return image
    }

    private func title(_ text: String) -> Label {
        let label = Label(text)
        label.addCSSClass("title-4")
        label.wrap = true
        label.selectable = true
        label.justify = GTK_JUSTIFY_CENTER
        label.pangoWrapMode = PANGO_WRAP_WORD_CHAR
        return label
    }

    private func subtitle(_ text: String) -> Label {
        let label = Label(text)
        label.addCSSClass(.dimLabel)
        label.wrap = true
        label.justify = GTK_JUSTIFY_CENTER
        return label
    }

    private func actions(_ labels: [String: String], order: [String]) -> Widget {
        let box = FlowBox()
        box.selectionMode = GTK_SELECTION_NONE
        box.maxChildrenPerLine = 2
        box.minChildrenPerLine = 1
        box.homogeneous = true
        for name in order {
            guard let text = labels[name] else { continue }
            let button = Button(label: text)
            button.onClicked { [weak self] in self?.onAction?(name) }
            box.append(button)
        }
        return box
    }

    /// A key/value list; rows without a value are left out.
    private func properties(_ rows: [(String, String?)]) -> Widget {
        let grid = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        grid.marginTop = 6
        for (key, value) in rows {
            guard let value, !value.isEmpty else { continue }
            let row = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
            let keyLabel = Label(key)
            keyLabel.xalign = 0
            keyLabel.addCSSClass(.dimLabel)
            keyLabel.addCSSClass("caption")
            let valueLabel = Label(value)
            valueLabel.xalign = 0
            valueLabel.wrap = true
            valueLabel.pangoWrapMode = PANGO_WRAP_WORD_CHAR
            valueLabel.selectable = true
            row.append(keyLabel)
            row.append(valueLabel)
            grid.append(row)
        }
        return grid
    }
}
