import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The path bar: clickable breadcrumbs, or the path as text to edit
/// (Ctrl+L, the pencil, or a click on the bar's empty space) — the Mac's
/// two presentations, with the same rules (`AddressBarEditor`). Tab
/// completes a folder name while typing.
@MainActor
final class PathBar {
    let widget: Box
    /// Called to navigate; the window points it at the focused pane.
    var onNavigate: ((URL) -> Void)?
    /// Crumb right-click: open the folder in a new tab / copy its path.
    var onOpenInNewTab: ((URL) -> Void)?
    var onCopyPath: ((URL) -> Void)?
    /// Files dropped on a crumb.
    var onDrop: (([URL], URL, Bool) -> Void)?
    /// Where a breadcrumb path starts: a drive's name for a path on it.
    var volumeRoots: () -> [(url: URL, name: String)] = { [] }

    private let stack = Stack()
    private let crumbs = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
    private let crumbScroller: ScrolledWindow
    private let entry = Entry()
    private var editor = AddressBarEditor(alwaysTextField: false, currentPath: "")
    private var currentURL: URL?
    private let resolver = PathResolver()

    init() {
        widget = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        widget.addCSSClass("oneroot-pathbar")
        widget.hexpand = true

        crumbs.addCSSClass("oneroot-crumbs")
        crumbScroller = ScrolledWindow(child: crumbs)
        crumbScroller.setPolicy(horizontal: GTK_POLICY_EXTERNAL, vertical: GTK_POLICY_NEVER)
        crumbScroller.hexpand = true

        let editButton = Button(iconName: "document-edit-symbolic")
        editButton.addCSSClass(.flat)
        editButton.tooltipText = "Type a Path (Ctrl+L)"
        editButton.setAccessibleLabel("Type a path")
        editButton.onClicked { [weak self] in self?.beginEditing() }
        editButtonRef = editButton

        let crumbRow = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        crumbRow.append(crumbScroller)
        crumbRow.append(editButton)
        // A click on the bar's empty space: type a path.
        let click = GestureClick()
        click.onReleased { [weak self] count, _, _ in
            guard count == 1 else { return }
            self?.beginEditing()
        }
        crumbScroller.addController(click)

        entry.hexpand = true
        entry.placeholderText = "Type a folder path, or ~ for Home"
        entry.inputHints = GTK_INPUT_HINT_NO_SPELLCHECK
        entry.onActivate { [weak self] in self?.submit() }
        entry.onChanged { [weak self] in self?.editor.textEdited(); self?.showError(nil) }
        let keys = EventControllerKey()
        keys.onKeyPressed { [weak self] keyval, _, _ in
            guard let self else { return false }
            switch keyval {
            case UInt32(GDK_KEY_Escape):
                self.cancelEditing()
                return true
            case UInt32(GDK_KEY_Tab):
                self.complete()
                return true
            default:
                return false
            }
        }
        gtk_event_controller_set_propagation_phase(OpaquePointer(keys.pointer), GTK_PHASE_CAPTURE)
        entry.addController(keys)
        let focus = EventControllerFocus()
        focus.onLeave { [weak self] in
            guard let self, self.editor.isEditing else { return }
            self.cancelEditing()
        }
        entry.addController(focus)

        stack.addNamed(crumbRow, name: "crumbs")
        stack.addNamed(entry, name: "entry")
        stack.hexpand = true
        stack.transitionType = GTK_STACK_TRANSITION_TYPE_CROSSFADE
        stack.transitionDuration = 100
        widget.append(stack)
        applyAddressBarStyle()
    }

    var isEditing: Bool { editor.isEditing }

    /// The focused pane's folder changed (or another pane took over).
    func show(_ url: URL?, paneChanged: Bool = false) {
        currentURL = url
        let path = url.flatMap { VirtualLocation(url: $0) == nil ? $0.path : nil } ?? ""
        if paneChanged {
            editor.paneChanged(currentPath: path)
            showMode()
        } else {
            editor.currentPathChanged(to: path, isTyping: entry.hasFocus)
            if !entry.hasFocus { entry.text = path }
        }
        rebuildCrumbs()
    }

    /// "Text field" address bar style: the path is always an editable field.
    private var usesTextField = false
    private var editButtonRef: Button?

    func applyAddressBarStyle() {
        let raw = UserDefaults.standard.string(forKey: AddressBarStyle.storageKey) ?? ""
        usesTextField = AddressBarStyle(rawValue: raw) == .textField
        editButtonRef?.visible = !usesTextField
        if usesTextField {
            if !entry.hasFocus { entry.text = currentURL?.path ?? "" }
        }
        showMode()
    }

    func beginEditing() {
        editor.begin(currentPath: currentURL?.path ?? "")
        entry.text = editor.text
        showMode()
        _ = entry.grabFocus()
        entry.selectAll()
    }

    func cancelEditing() {
        editor.cancel(currentPath: currentURL?.path ?? "")
        if usesTextField { entry.text = currentURL?.path ?? "" }
        showError(nil)
        showMode()
    }

    private func submit() {
        editor.text = entry.text
        switch editor.submit(resolver.resolve(entry.text)) {
        case .navigate(let url):
            onNavigate?(url)
            editor.finish(currentPath: url.path)
            showMode()
        case .connect(let url):
            connect(to: url)
        case .stay:
            showError(editor.errorMessage)
        }
    }

    /// smb://, afp://, nfs://, sftp://, ftp://, dav:// — mounted through
    /// GIO (gvfs), then opened. A location that needs a login says so; Connect
    /// to Server (Ctrl+K) takes one.
    private func connect(to url: URL) {
        let address = url.absoluteString
        entry.progressPulse()
        Task { [weak self] in
            do {
                let mounted = try await NetworkMounter().mount(url, credentials: await ConnectToServerDialog.savedCredentials(for: url))
                guard let self else { return }
                self.entry.progressFraction = 0
                self.onNavigate?(mounted)
                self.editor.finish(currentPath: mounted.path)
                self.showMode()
            } catch {
                guard let self else { return }
                self.entry.progressFraction = 0
                var message = error.localizedDescription
                if case NetworkMounter.Failure.needsLogin = error { message += " Use Connect to Server (Ctrl+K)." }
                self.editor.connectionFailed(message.isEmpty ? "Couldn\u{2019}t connect to \(address)." : message)
                self.showError(self.editor.errorMessage)
            }
        }
    }

    /// Tab: completes the folder name being typed as far as it's unique.
    private func complete() {
        let text = entry.text
        guard let split = resolver.splitForAutocomplete(text) else { return }
        let directory = split.directory
        let prefix = split.prefix
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let matches = names.filter { name in
            guard prefix.hasPrefix(".") || !name.hasPrefix(".") else { return false }
            guard name.lowercased().hasPrefix(prefix.lowercased()) else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path, isDirectory: &isDirectory) && isDirectory.boolValue
        }.sorted()
        guard let first = matches.first else {
            gtk_widget_error_bell(entry.widgetPointer)
            return
        }
        var common = first
        for name in matches.dropFirst() {
            while !name.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        let base = text.hasSuffix("/") ? text : String(text[..<(text.lastIndex(of: "/").map { text.index(after: $0) } ?? text.startIndex)])
        entry.text = base + common + (matches.count == 1 ? "/" : "")
        entry.cursorPosition = -1
    }

    private func showMode() {
        stack.visibleChildName = (editor.isEditing || usesTextField) ? "entry" : "crumbs"
    }

    private func showError(_ message: String?) {
        if let message {
            entry.addCSSClass(.error)
            entry.tooltipText = message
            entry.setIcon(position: GTK_ENTRY_ICON_SECONDARY, iconName: "dialog-warning-symbolic")
            entry.setIconTooltip(position: GTK_ENTRY_ICON_SECONDARY, tooltip: message)
        } else {
            entry.removeCSSClass(.error)
            entry.tooltipText = nil
            entry.setIcon(position: GTK_ENTRY_ICON_SECONDARY, iconName: nil)
        }
    }

    // MARK: Breadcrumbs

    private func rebuildCrumbs() {
        while let child = crumbs.firstChild { crumbs.remove(child) }
        guard let url = currentURL else { return }
        // Recents isn't a folder: one crumb with its name (and no path to show).
        let segments = VirtualLocation(url: url).map { [Segment(name: $0.title, icon: "document-open-recent-symbolic", url: url)] }
            ?? Self.segments(for: url, volumes: volumeRoots())
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                let separator = Label("/")
                separator.addCSSClass(.dimLabel)
                crumbs.append(separator)
            }
            let button = Button()
            let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
            if let icon = segment.icon { content.append(Image(iconName: icon)) }
            if !segment.name.isEmpty {
                let label = Label(segment.name)
                label.ellipsize = PANGO_ELLIPSIZE_MIDDLE
                label.maxWidthChars = 24
                content.append(label)
            }
            button.child = content
            button.addCSSClass(.flat)
            if index == segments.count - 1 { button.addCSSClass("oneroot-crumb-current") }
            button.tooltipText = VirtualLocation(url: segment.url) == nil ? segment.url.path : segment.name
            let target = segment.url
            button.onClicked { [weak self] in self?.onNavigate?(target) }
            let rightClick = GestureClick()
            rightClick.button = 3
            rightClick.onPressed { [weak self, weak button] _, _, _ in
                guard let self, let button else { return }
                self.showCrumbMenu(for: target, from: button)
            }
            button.addController(rightClick)
            let buttonPointer = button.pointer
            DragAndDrop.attachFileTarget(to: button, destination: { VirtualLocation(url: target) == nil ? target : nil }, highlight: { on in
                let widget = buttonPointer.assumingMemoryBound(to: GtkWidget.self)
                if on { gtk_widget_add_css_class(widget, "oneroot-drop-target") } else { gtk_widget_remove_css_class(widget, "oneroot-drop-target") }
            }, drop: { [weak self] urls, folder, move in
                self?.onDrop?(urls, folder, move)
            })
            crumbs.append(button)
            if VirtualLocation(url: target) == nil {
                let chevron = Button(iconName: "pan-down-symbolic")
                chevron.addCSSClass(.flat)
                chevron.addCSSClass("oneroot-crumb-chevron")
                chevron.tooltipText = "Folders in \(segment.name.isEmpty ? "/" : segment.name)"
                chevron.setAccessibleLabel("Subfolders of \(segment.name.isEmpty ? "the computer" : segment.name)")
                chevron.onClicked { [weak self, weak chevron] in
                    guard let self, let chevron else { return }
                    self.showSubfolders(of: target, from: chevron)
                }
                crumbs.append(chevron)
            }
        }
        // Keep the end of a long path in view.
        MainContext.task { [weak self] in
            guard let adjustment = self?.crumbScroller.horizontalAdjustment else { return }
            adjustment.value = adjustment.upper
        }
    }

    // MARK: Crumb menus

    private func showCrumbMenu(for url: URL, from anchor: Widget) {
        LocationListPopover.show([
            .init("Open", icon: "folder-open-symbolic") { [weak self] in self?.onNavigate?(url) },
            .init("Open in New Tab", icon: "tab-new-symbolic") { [weak self] in self?.onOpenInNewTab?(url) },
            .init("Copy Path", icon: "edit-copy-symbolic") { [weak self] in self?.onCopyPath?(url) },
        ], from: anchor, label: "Folder actions")
    }

    /// The chevron after a crumb: that folder's subfolders, listed off the
    /// main thread (hidden ones skipped).
    private func showSubfolders(of url: URL, from anchor: Widget) {
        Task { [weak self, weak anchor] in
            let names = await Task.detached(priority: .userInitiated) { () -> [String] in
                let keys: [URLResourceKey] = [.isDirectoryKey]
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
                return entries
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .map(\.lastPathComponent)
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }.value
            guard let self, let anchor else { return }
            let shown = names.prefix(300)
            var items = shown.map { name in
                LocationListPopover.Item(name, icon: "folder-symbolic") { [weak self] in
                    self?.onNavigate?(url.appendingPathComponent(name, isDirectory: true))
                }
            }
            if items.isEmpty { items = [.init("No Subfolders") {}] }
            LocationListPopover.show(items, from: anchor, label: "Subfolders")
        }
    }

    struct Segment: Equatable {
        let name: String
        let icon: String?
        let url: URL
    }

    /// Home and what's inside it starts at Home; a drive's contents at the
    /// drive; anything else at the computer's root, as in Nautilus.
    static func segments(for url: URL, volumes: [(url: URL, name: String)], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Segment] {
        let path = url.standardizedFileURL.path
        var roots: [(url: URL, name: String, icon: String)] = [(home, "Home", "user-home-symbolic")]
        roots += volumes.filter { $0.url.path != "/" }.map { ($0.url, $0.name, "drive-harddisk-symbolic") }
        let root = roots
            .filter { root in
                let rootPath = root.url.standardizedFileURL.path
                return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
            }
            .max { $0.url.path.count < $1.url.path.count }
            ?? (URL(fileURLWithPath: "/", isDirectory: true), "", "drive-harddisk-symbolic")
        var segments = [Segment(name: root.name, icon: root.icon, url: root.url)]
        let rootPath = root.url.standardizedFileURL.path
        let rest = path.dropFirst(rootPath.count).split(separator: "/")
        var current = root.url
        for component in rest {
            current = current.appendingPathComponent(String(component), isDirectory: true)
            segments.append(Segment(name: String(component), icon: nil, url: current))
        }
        return segments
    }
}
