import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Quick Look (Space or Ctrl+Y): a window that previews the selected file
/// and follows the selection as it changes. Images and text are shown; a
/// folder or anything else shows its icon and basic facts. Reading happens
/// off the main thread and a newer selection cancels the older read.
/// One instance on `OneRootApp`.
@MainActor
final class QuickLookWindow {
    let window: ApplicationWindow
    var onClose: (() -> Void)?

    static let imagePixels = 2000
    static let textBytes = 64 * 1024
    static let imageSizeLimit: Int64 = 200 * 1024 * 1024

    private let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private var pane: FileListViewModel?
    private var watch: ObservationWatch?
    private var task: Task<Void, Never>?
    private var generation = 0
    /// Which of a multi-selection is showing (Left/Right step through them).
    private var galleryIndex = 0
    private var lastSelection: [URL] = []

    static let videoExtensions: Set<String> = ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "mpg", "mpeg"]
    static let audioExtensions: Set<String> = ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac", "wma"]

    static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) || audioExtensions.contains(ext)
    }

    /// The index after stepping `delta` through `count` items, stopping at the ends.
    nonisolated static func stepped(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    init(application: Application) {
        window = ApplicationWindow(application: application)
        window.title = "Quick Look"
        window.defaultWidth = 760
        window.defaultHeight = 560
        content.hexpand = true
        content.vexpand = true
        let toolbar = ToolbarView()
        toolbar.addTopBar(HeaderBar())
        toolbar.setContent(content)
        window.setContent(toolbar)
        window.onCloseRequest { [weak self] in
            self?.task?.cancel()
            self?.watch = nil
            self?.onClose?()
            return false
        }
        let keys = EventControllerKey()
        keys.onKeyPressed { [weak self] keyval, _, _ in
            switch keyval {
            case UInt32(GDK_KEY_space), UInt32(GDK_KEY_Escape):
                self?.window.close()
                return true
            case UInt32(GDK_KEY_Left), UInt32(GDK_KEY_Up):
                self?.step(-1)
                return true
            case UInt32(GDK_KEY_Right), UInt32(GDK_KEY_Down):
                self?.step(1)
                return true
            default:
                return false
            }
        }
        window.addController(keys)
    }

    func present(for pane: FileListViewModel) {
        bind(to: pane)
        window.present()
    }

    /// Follows `pane`'s selection (the active tab changed, or it opened).
    func bind(to pane: FileListViewModel) {
        self.pane = pane
        watch = ObservationWatch.watch({ pane.selectedNodes.map(\.url) }) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Arrow keys: through a multi-selection, or else the list selection
    /// moves to the neighbouring item and Quick Look follows.
    private func step(_ delta: Int) {
        guard let pane else { return }
        let selected = pane.selectedNodes
        if selected.count > 1 {
            galleryIndex = Self.stepped(galleryIndex, by: delta, count: selected.count)
            refresh(keepingIndex: true)
            return
        }
        let items = pane.items
        guard let current = selected.first, let at = items.firstIndex(where: { $0.url == current.url }) else { return }
        let next = Self.stepped(at, by: delta, count: items.count)
        if next != at { pane.reveal(items[next].url) }
    }

    // MARK: Showing

    private func refresh(keepingIndex: Bool = false) {
        task?.cancel()
        generation += 1
        let token = generation
        guard let pane else { return }
        let nodes = pane.selectedNodes
        let urls = nodes.map(\.url)
        if !keepingIndex, urls != lastSelection { galleryIndex = 0 }
        lastSelection = urls
        galleryIndex = min(galleryIndex, max(nodes.count - 1, 0))
        guard nodes.indices.contains(galleryIndex) else {
            window.title = "Quick Look"
            show(message: "Select a file to preview it.")
            return
        }
        let node = nodes[galleryIndex]
        window.title = nodes.count > 1 ? "\(node.name) (\(galleryIndex + 1) of \(nodes.count))" : node.name
        let url = node.url
        if !node.isDirectory, Self.isMedia(url) {
            showMedia(url, name: node.name)
            return
        }
        let isDirectory = node.isDirectory
        let wantsImage = !isDirectory && InspectorPane.hasPagePreview(node) && (node.size ?? 0) <= Self.imageSizeLimit
        let wantsText = !isDirectory && !wantsImage && (node.size ?? 0) > 0
        show(message: "Loading…")
        task = Task { [weak self] in
            let (text, image, error): (String?, DecodedImage?, String?) = await Task.detached(priority: .userInitiated) {
                if wantsImage {
                    let image = InspectorPane.decodePreview(url, maxSize: Self.imagePixels)
                    return (nil, image, image == nil ? "This file can't be previewed." : nil)
                }
                if wantsText { return (ItemInfo.text(at: url, bytes: Self.textBytes), nil, nil) }
                return (nil, nil, nil)
            }.value
            guard let self, !Task.isCancelled, token == self.generation else { return }
            if let image, let texture = image.makeTexture() {
                self.showImage(texture, name: node.name)
            } else if let text {
                self.showText(text, name: node.name, markdown: InspectorPane.isMarkdown(url))
            } else if let error {
                self.show(message: error)
            } else {
                self.showDetails(node)
            }
        }
    }

    private func replaceContent(with widget: Widget) {
        while let child = content.firstChild { content.remove(child) }
        widget.hexpand = true
        widget.vexpand = true
        content.append(widget)
    }

    private func show(message: String) {
        let label = Label(message)
        label.addCSSClass("dim-label")
        label.setAccessibleLabel(message)
        replaceContent(with: label)
    }

    /// Audio and video play in GTK's own media widget (GStreamer), paused
    /// until asked. Replacing the content on the next selection stops it.
    private func showMedia(_ url: URL, name: String) {
        guard let video = gtk_video_new_for_filename(url.path) else {
            show(message: "This file can't be played.")
            return
        }
        gtk_video_set_autoplay(OpaquePointer(video), 0)
        let widget = Widget(borrowing: UnsafeMutableRawPointer(video))
        widget.setAccessibleLabel("Player for \(name)")
        replaceContent(with: widget)
    }

    private func showImage(_ texture: Texture, name: String) {
        let picture = Picture()
        picture.setPaintable(texture)
        picture.canShrink = true
        picture.contentFit = GTK_CONTENT_FIT_CONTAIN
        picture.marginStart = 12
        picture.marginEnd = 12
        picture.marginTop = 12
        picture.marginBottom = 12
        picture.setAccessibleLabel("Preview of \(name)")
        replaceContent(with: picture)
    }

    private func showText(_ text: String, name: String, markdown: Bool = false) {
        let label = Label("")
        if markdown {
            // A Markdown file as it reads.
            label.markup = MarkdownPango.markup(from: text)
            label.wrap = true
        } else {
            label.text = text
            label.addCSSClass("monospace")
        }
        label.xalign = 0
        label.yalign = 0
        label.selectable = true
        label.marginStart = 14
        label.marginEnd = 14
        label.marginTop = 14
        label.marginBottom = 14
        label.setAccessibleLabel("Text preview of \(name)")
        let scroller = ScrolledWindow(child: label)
        scroller.setPolicy(horizontal: GTK_POLICY_AUTOMATIC, vertical: GTK_POLICY_AUTOMATIC)
        replaceContent(with: scroller)
    }

    /// Folders and files with no preview: icon, name, kind, size.
    private func showDetails(_ node: FileNode) {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        box.halign = GTK_ALIGN_CENTER
        box.valign = GTK_ALIGN_CENTER
        let icon = Image()
        icon.pixelSize = 96
        FileIcons.set(icon, to: node)
        box.append(icon)
        let name = Label(node.name)
        name.addCSSClass("title-2")
        name.wrap = true
        box.append(name)
        var facts: [String] = [node.isDirectory ? "Folder" : (node.kind ?? "File")]
        if !node.isDirectory, let size = node.size { facts.append(Formatting.size(size)) }
        let detail = Label(facts.joined(separator: " \u{00B7} "))
        detail.addCSSClass("dim-label")
        box.append(detail)
        replaceContent(with: box)
    }
}
