import AppKit
import QuickLookUI

/// Everything you can *do* to the selected files, shared by every way of
/// showing a folder — the list (`FileTableController`) and the icon grid
/// (`FileIconController`): the right-click menu, keyboard actions, Quick
/// Look, and what double-click does. Each view supplies its own selection
/// (`selectionProvider`) and right-click target; everything else lives
/// here once, so a new menu item or shortcut can't end up in one view and
/// not the other.
///
/// Like the controllers, this never talks to services or view models
/// directly — intent flows out through the closures `FileListView` sets.
@MainActor
final class FileItemActions: NSObject, NSMenuDelegate, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// The hosting view's current selection, in display order.
    var selectionProvider: () -> [FileNode] = { [] }
    /// The view that gets keyboard focus for Quick Look — QuickLookUI finds
    /// the panel's data source by walking the responder chain from there.
    weak var hostView: NSView?
    /// Set by the hosting view right before showing the context menu: true
    /// if the right-click landed on empty space rather than an item.
    var isBackgroundRightClick = false
    /// What the Quick Look panel is showing.
    private(set) var quickLookURLs: [URL] = []

    /// `openInNewTab` reflects whether Cmd was held (double-click), the
    /// context menu's/⇧⌘T's "Open in New Tab" was used, or the sidebar's
    /// own "Open in New Tab" affordance was used.
    var onOpenFolder: ((_ node: FileNode, _ openInNewTab: Bool) -> Void)?
    var onCopy: (([FileNode]) -> Void)?
    var onDuplicate: (([FileNode]) -> Void)?
    var onCut: (([FileNode]) -> Void)?
    var onPaste: (() -> Void)?
    var onRename: ((FileNode) -> Void)?
    /// Several items selected: the batch Rename dialog.
    var onBatchRename: (([FileNode]) -> Void)?
    /// Esc: clear the selection.
    var onDeselectAll: (() -> Void)?
    /// Context menu ▸ Calculate Size, for the selected folders.
    var onCalculateSize: (([FileNode]) -> Void)?
    var onMoveToTrash: (([FileNode]) -> Void)?
    var onNewFolder: (() -> Void)?
    var onNewFolderAndOpen: (() -> Void)?
    var onNewFolderHere: ((FileNode) -> Void)?
    var onNewFile: (() -> Void)?
    var onCopyPath: ((FileNode) -> Void)?
    var onCopyNames: (([FileNode], _ includeExtension: Bool) -> Void)?
    var onCopyViaSSH: (([FileNode]) -> Void)?
    var onRestore: (([FileNode]) -> Void)?
    var onDeletePermanently: (([FileNode]) -> Void)?
    var onCompress: (([FileNode]) -> Void)?
    var onExtract: (([FileNode]) -> Void)?
    var canExtract: (([FileNode]) -> Bool)?
    /// The context menu's Quick Actions submenu: what applies, and running one.
    var quickActionOptions: (([FileNode]) -> [QuickActionOption])?
    var onQuickAction: ((QuickAction, [FileNode]) -> Void)?
    /// Tags ▸: the tags to offer, and putting one on (`true`) or taking it
    /// off every selected item.
    var tagSuggestions: (() -> [String])?
    var onSetTag: ((String, Bool, [FileNode]) -> Void)?
    var canPaste: (() -> Bool)?
    /// `targetNode` is `nil` for a background drop, meaning "the current
    /// directory" — the views don't know what that is, only the view
    /// model does.
    var onDrop: ((_ urls: [URL], _ targetNode: FileNode?, _ move: Bool) -> Void)?
    var onMakeAliases: ((_ urls: [URL], _ targetNode: FileNode?) -> Void)?
    /// Set by `FileListView` when the current directory is Trash — swaps
    /// "Move to Trash" for "Restore"/"Delete Immediately" everywhere.
    var isViewingTrash = false
    /// Split tabs only (`nil` otherwise): copy (`move: false`) or move the
    /// selection into the other pane's folder — F5/F6, ⇧⌘C/⇧⌘M, or the
    /// context menu.
    var onSendToOtherPane: ((_ nodes: [FileNode], _ move: Bool) -> Void)?
    /// The hosting view just became first responder — in a split tab, that
    /// makes its pane the focused one.
    var onFocus: (() -> Void)?


    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var selectedNodes: [FileNode] { selectionProvider() }

    private static let returnKeyCodes: Set<UInt16> = [36, 76] // Return, keypad Enter
    private static let deleteKeyCodes: Set<UInt16> = [51, 117] // Delete/Backspace, Forward Delete
    private static let f5KeyCode: UInt16 = 96
    private static let f6KeyCode: UInt16 = 97
    private static let escapeKeyCode: UInt16 = 53

    /// The keys every file view handles the same way. Returns `false` for
    /// anything else, so the view passes it on to its own `super.keyDown`
    /// (arrow-key selection, type-to-select, …). Checks raw key codes
    /// directly rather than relying on `doCommand(by:)` — `NSTableView`
    /// doesn't consistently forward Return/Delete through that path, so
    /// `doCommand(by:)` silently never fired for them in testing.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let key = event.charactersIgnoringModifiers?.lowercased()
        if onSendToOtherPane != nil, event.keyCode == Self.f5KeyCode || (flags.contains([.command, .shift]) && key == "c") {
            // F5/F6 is the Commander convention; on most Mac keyboards those
            // keys need fn, hence ⇧⌘C/⇧⌘M too.
            sendToOtherPane(move: false)
        } else if onSendToOtherPane != nil, event.keyCode == Self.f6KeyCode || (flags.contains([.command, .shift]) && key == "m") {
            sendToOtherPane(move: true)
        } else if event.keyCode == Self.escapeKeyCode, flags.intersection(.deviceIndependentFlagsMask).isEmpty, !selectedNodes.isEmpty {
            // Esc deselects, like the Context Bar's ✕ (and ⌥⌘A).
            onDeselectAll?()
        } else if Self.returnKeyCodes.contains(event.keyCode) {
            // Return renames (matching Finder) rather than opening — ⌘O took over that role.
            handleRename()
        } else if flags.contains([.command, .shift]), key == "t" {
            handleOpenInNewTab()
        } else if flags.contains(.command), key == "o" {
            handleOpen()
        } else if flags.contains(.command), key == "l" {
            handleRevealInFinder()
        } else if Self.deleteKeyCodes.contains(event.keyCode) {
            handleMoveToTrash()
        } else if event.charactersIgnoringModifiers == " " {
            handleQuickLook()
        } else {
            return false
        }
        return true
    }

    /// Double-click (or the icon view's equivalent) on `node`: navigate into
    /// a folder (⌘ for a new tab), extract an archive, or open a file.
    func openOnDoubleClick(_ node: FileNode) {
        if isNavigable(node) {
            let openInNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            onOpenFolder?(node, openInNewTab)
        } else if canExtract?([node]) ?? false {
            onExtract?([node])
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    // MARK: Actions (shared by context menu and keyboard shortcuts)

    /// A `.app` bundle (or other package) is a directory on disk but should
    /// behave like a single launchable file — Open/double-click launches it
    /// rather than navigating in. Option-⌘O (or Option-clicking "Open")
    /// overrides that to browse into it as a folder instead.
    private func isNavigable(_ node: FileNode) -> Bool {
        node.isNavigable(browsePackage: NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }

    private func handleOpen() {
        guard let node = selectedNodes.first else { return }
        if isNavigable(node) {
            onOpenFolder?(node, false)
        } else if canExtract?([node]) ?? false {
            onExtract?([node])
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    private func handleOpenInNewTab() {
        guard let node = selectedNodes.first, isNavigable(node) else { return }
        onOpenFolder?(node, true)
    }

    /// Not `private` — also called from the representables' `updateNSView`
    /// when the main menu's ⌘Y "Quick Look" command bumps
    /// `FileListViewModel.quickLookTrigger`, so the same panel logic backs
    /// both the Space key (scoped to the view) and the global menu command.
    func handleQuickLook() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        quickLookURLs = nodes.map(\.url)
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if let hostView { hostView.window?.makeFirstResponder(hostView) }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func handleCopy() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onCopy?(nodes)
    }

    func handleCut() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onCut?(nodes)
    }

    func handlePaste() {
        onPaste?()
    }

    /// Return, or the menu's Rename: one item renames in place, several
    /// open the batch Rename dialog.
    @objc private func handleRename() {
        let nodes = selectedNodes
        if nodes.count > 1 {
            onBatchRename?(nodes)
        } else if let node = nodes.first {
            onRename?(node)
        }
    }

    private func handleMoveToTrash() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        if isViewingTrash {
            confirmAndDeletePermanently(nodes)
        } else if TrashConfirmation.confirm(nodes.map(\.name)) {
            onMoveToTrash?(nodes)
        }
    }

    private func confirmAndDeletePermanently(_ nodes: [FileNode]) {
        let alert = NSAlert()
        alert.messageText = nodes.count == 1
            ? "Delete \"\(nodes[0].name)\" immediately?"
            : "Delete \(nodes.count) items immediately?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Delete Immediately")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDeletePermanently?(nodes)
    }

    @objc private func handleCopyPath() {
        guard let node = selectedNodes.first else { return }
        onCopyPath?(node)
    }

    /// A drop on the list or grid: ⌃ held asks Move / Copy / Make Alias
    /// (`DropActionMenu`); otherwise the drag's own operation decides.
    func drop(_ urls: [URL], on targetNode: FileNode?, info: NSDraggingInfo) {
        guard DropActionMenu.shouldAsk(for: info) else {
            onDrop?(urls, targetNode, info.draggingSourceOperationMask.contains(.move))
            return
        }
        DropActionMenu.ask { [weak self] action in
            switch action {
            case .move: self?.onDrop?(urls, targetNode, true)
            case .copy: self?.onDrop?(urls, targetNode, false)
            case .alias: self?.onMakeAliases?(urls, targetNode)
            }
        }
    }

    @objc private func handleCopyName() {
        onCopyNames?(selectedNodes, true)
    }

    @objc private func handleCopyNameWithoutExtension() {
        onCopyNames?(selectedNodes, false)
    }

    @objc private func handleRevealInFinder() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(nodes.map(\.url))
    }

    @objc private func handleCopyViaSSH() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onCopyViaSSH?(nodes)
    }

    @objc private func handleCompress() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onCompress?(nodes)
    }

    @objc private func handleQuickAction(_ sender: NSMenuItem) {
        let nodes = selectedNodes
        guard !nodes.isEmpty,
              let raw = sender.representedObject as? String,
              let action = QuickAction(rawValue: raw)
        else { return }
        onQuickAction?(action, nodes)
    }

    /// "Quick Actions ▸" — the ones that don't apply to the whole
    /// selection are shown disabled, with the reason as a tooltip.
    private func makeQuickActionsItem(for nodes: [FileNode]) -> NSMenuItem? {
        let options = quickActionOptions?(nodes) ?? []
        guard !options.isEmpty else { return nil }
        let submenu = NSMenu(title: "Quick Actions")
        submenu.autoenablesItems = false
        for option in options {
            let item = makeItem(option.action.menuTitle, #selector(handleQuickAction(_:)))
            item.representedObject = option.action.rawValue
            item.image = NSImage(systemSymbolName: option.action.systemImage, accessibilityDescription: nil)
            item.isEnabled = option.isAvailable
            item.toolTip = option.unavailableReason
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// "Tags ▸" — each tag with a checkmark when every selected item has
    /// it, a dash when only some do. Choosing it puts it on them all, or
    /// takes it off if they all have it already.
    private func makeTagsItem(for nodes: [FileNode]) -> NSMenuItem? {
        guard onSetTag != nil, let suggestions = tagSuggestions?() else { return nil }
        let usage = TagService.usage(in: nodes.map(\.tags))
        var tags = usage.map(\.tag)
        for tag in suggestions where !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tags.append(tag)
        }
        let submenu = NSMenu(title: "Tags")
        submenu.autoenablesItems = false
        for tag in tags {
            let item = makeItem(tag, #selector(handleToggleTag(_:)))
            item.representedObject = tag
            let count = usage.first { $0.tag.caseInsensitiveCompare(tag) == .orderedSame }?.count ?? 0
            item.state = count == nodes.count ? .on : (count > 0 ? .mixed : .off)
            item.image = Self.tagDot(TagColors.color(for: tag))
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func handleToggleTag(_ sender: NSMenuItem) {
        let nodes = selectedNodes
        guard !nodes.isEmpty, let tag = sender.representedObject as? String else { return }
        // Already on every item: take it off. Otherwise put it on them all.
        onSetTag?(tag, sender.state != .on, nodes)
    }

    private static func tagDot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    @objc private func handleExtract() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onExtract?(nodes)
    }

    @objc private func handleOpenInTerminal() {
        guard let node = selectedNodes.first else { return }
        openInTerminal(node.isDirectory ? node.url : node.url.deletingLastPathComponent())
    }

    @objc private func handleGetInfo() {
        guard let node = selectedNodes.first else { return }
        let alert = NSAlert()
        alert.messageText = node.name
        var lines = ["Kind: \(node.isDirectory ? "Folder" : (node.kind ?? "Unknown"))"]
        if !node.isDirectory, let size = node.size {
            lines.append("Size: \(Self.byteFormatter.string(fromByteCount: size))")
        }
        if let date = node.modificationDate {
            lines.append("Modified: \(FileDateFormat.string(from: date))")
        }
        lines.append("Location: \(node.url.deletingLastPathComponent().path)")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func handleNewFolder() {
        onNewFolder?()
    }

    @objc private func handleNewFolderAndOpen() {
        onNewFolderAndOpen?()
    }

    @objc private func handleNewFolderHere() {
        guard let node = selectedNodes.first, node.isDirectory else { return }
        onNewFolderHere?(node)
    }

    @objc private func handleNewFile() {
        onNewFile?()
    }

    private func openWithApp(_ appURL: URL, for url: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard !isBackgroundRightClick else {
            // Nothing in the background menu (Paste, New Folder…) makes
            // sense while viewing Trash — you can't create or paste
            // things into it — so it's just empty there.
            if !isViewingTrash {
                appendPasteAndNewFolder(to: menu)
            }
            return
        }

        let nodes = selectedNodes
        guard let node = nodes.first else { return }

        // Trash items only support Restore/Delete Immediately — every
        // other action (Open, Rename, Cut/Copy/Paste, Get Info, New
        // Folder…) either doesn't apply to something already in the
        // Trash or would fight with Finder's own Trash semantics.
        if isViewingTrash {
            menu.addItem(makeItem("Restore", #selector(handleRestoreMenuAction)))
            menu.addItem(makeItem("Delete Immediately", #selector(handleDeleteImmediatelyMenuAction)))
            return
        }

        let openItem = makeItem("Open", #selector(handleOpenMenuAction))
        openItem.keyEquivalent = "o"
        openItem.keyEquivalentModifierMask = .command
        menu.addItem(openItem)

        if nodes.count == 1, isNavigable(node) {
            let openInNewTabItem = makeItem("Open in New Tab", #selector(handleOpenInNewTabMenuAction))
            openInNewTabItem.keyEquivalent = "t"
            openInNewTabItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(openInNewTabItem)
        }

        if nodes.count == 1, node.isPackage {
            let showContentsItem = makeItem("Show Package Contents", #selector(handleShowPackageContentsMenuAction))
            showContentsItem.keyEquivalent = "o"
            showContentsItem.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(showContentsItem)
        }

        let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWithItem.submenu = buildOpenWithSubmenu(for: node)
        menu.addItem(openWithItem)

        menu.addItem(makeItem("Quick Look", #selector(handleQuickLookMenuAction)))
        if canExtract?(nodes) ?? false {
            menu.addItem(makeItem("Extract", #selector(handleExtract)))
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("Cut", #selector(handleCutMenuAction)))
        menu.addItem(makeItem("Copy", #selector(handleCopyMenuAction)))
        let duplicateItem = makeItem("Duplicate", #selector(handleDuplicate))
        duplicateItem.keyEquivalent = "d"
        duplicateItem.keyEquivalentModifierMask = .command
        menu.addItem(duplicateItem)
        let pasteItem = makeItem("Paste", #selector(handlePasteMenuAction))
        pasteItem.isEnabled = canPaste?() ?? false
        menu.addItem(pasteItem)
        if onSendToOtherPane != nil {
            menu.addItem(.separator())
            let copyItem = makeItem("Copy to Other Pane", #selector(handleCopyToOtherPane))
            copyItem.keyEquivalent = "c"
            copyItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(copyItem)
            let moveItem = makeItem("Move to Other Pane", #selector(handleMoveToOtherPane))
            moveItem.keyEquivalent = "m"
            moveItem.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(moveItem)
        }
        menu.addItem(.separator())
        menu.addItem(makeItem(nodes.count == 1 ? "Compress \"\(node.name)\"" : "Compress \(nodes.count) Items", #selector(handleCompress)))
        if let quickActions = makeQuickActionsItem(for: nodes) {
            menu.addItem(quickActions)
        }
        if let tags = makeTagsItem(for: nodes) {
            menu.addItem(tags)
        }
        menu.addItem(.separator())

        menu.addItem(makeItem(nodes.count == 1 ? "Rename" : "Rename \(nodes.count) Items\u{2026}", #selector(handleRename)))
        menu.addItem(makeItem("Move to Trash", #selector(handleMoveToTrashMenuAction)))
        menu.addItem(.separator())

        // Not when every folder's size is worked out anyway (Settings).
        if nodes.contains(where: \.isDirectory), !FolderSizePreferenceStore.shared.calculateAll {
            menu.addItem(makeItem("Calculate Size", #selector(handleCalculateSize)))
        }
        if nodes.count == 1 {
            menu.addItem(makeItem("Get Info", #selector(handleGetInfo)))
            menu.addItem(makeItem("Copy Path", #selector(handleCopyPath)))
        }
        menu.addItem(makeItem(nodes.count == 1 ? "Copy Name" : "Copy Names", #selector(handleCopyName)))
        if nodes.contains(where: CopyableName.hasStrippableExtension) {
            menu.addItem(makeItem(nodes.count == 1 ? "Copy Name without Extension" : "Copy Names without Extensions", #selector(handleCopyNameWithoutExtension)))
        }
        if nodes.count == 1 {
            menu.addItem(makeItem("Open in Terminal", #selector(handleOpenInTerminal)))
        }
        menu.addItem(.separator())

        let revealInFinderItem = makeItem("Reveal in Finder", #selector(handleRevealInFinder))
        revealInFinderItem.keyEquivalent = "l"
        revealInFinderItem.keyEquivalentModifierMask = .command
        menu.addItem(revealInFinderItem)
        menu.addItem(makeItem("Copy via SSH…", #selector(handleCopyViaSSH)))
        menu.addItem(.separator())

        menu.addItem(makeItem("New Folder", #selector(handleNewFolder)))
        menu.addItem(makeItem("New Folder and Open", #selector(handleNewFolderAndOpen)))
        if nodes.count == 1, node.isDirectory {
            menu.addItem(makeItem("New Folder Here", #selector(handleNewFolderHere)))
        }
        menu.addItem(makeItem("New File", #selector(handleNewFile)))
    }

    private func sendToOtherPane(move: Bool) {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onSendToOtherPane?(nodes, move)
    }

    @objc private func handleCalculateSize() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onCalculateSize?(nodes)
    }

    @objc private func handleCopyToOtherPane() { sendToOtherPane(move: false) }
    @objc private func handleMoveToOtherPane() { sendToOtherPane(move: true) }

    private func appendPasteAndNewFolder(to menu: NSMenu) {
        let pasteItem = makeItem("Paste", #selector(handlePasteMenuAction))
        pasteItem.isEnabled = canPaste?() ?? false
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        menu.addItem(makeItem("New Folder", #selector(handleNewFolder)))
        menu.addItem(makeItem("New Folder and Open", #selector(handleNewFolderAndOpen)))
        menu.addItem(makeItem("New File", #selector(handleNewFile)))
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func handleOpenMenuAction() { handleOpen() }
    @objc private func handleOpenInNewTabMenuAction() { handleOpenInNewTab() }
    @objc private func handleShowPackageContentsMenuAction() {
        guard let node = selectedNodes.first, node.isPackage else { return }
        onOpenFolder?(node, false)
    }
    @objc private func handleQuickLookMenuAction() { handleQuickLook() }
    @objc private func handleCutMenuAction() { handleCut() }
    @objc private func handleCopyMenuAction() { handleCopy() }
    @objc private func handleDuplicate() { onDuplicate?(selectedNodes) }
    @objc private func handlePasteMenuAction() { handlePaste() }
    @objc private func handleMoveToTrashMenuAction() { handleMoveToTrash() }

    @objc private func handleRestoreMenuAction() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        onRestore?(nodes)
    }

    @objc private func handleDeleteImmediatelyMenuAction() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        confirmAndDeletePermanently(nodes)
    }

    private func buildOpenWithSubmenu(for node: FileNode) -> NSMenu {
        if node.isDirectory {
            return buildFolderOpenWithSubmenu(for: node.url)
        }
        let submenu = NSMenu()
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: node.url)
        guard !appURLs.isEmpty else {
            let empty = NSMenuItem(title: "No applications available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }
        for appURL in appURLs {
            submenu.addItem(openWithMenuItem(appURL: appURL, fileURL: node.url))
        }
        return submenu
    }

    /// Folders get two pinned entries ahead of whatever LaunchServices
    /// auto-discovers (`NSWorkspace.urlsForApplications(toOpen:)`):
    /// Terminal (via `openInTerminal`, same as the top-level "Open in
    /// Terminal" item) and, if one's configured in Settings, an Editor
    /// (via `openInEditor`). Both exist as pinned entries rather than
    /// relying on auto-discovery because most terminal apps — including
    /// Terminal.app itself — and plenty of editors (VS Code being the
    /// canonical example) open folders just fine but don't declare that
    /// in their own `Info.plist`, so LaunchServices never offers them.
    /// Everything LaunchServices *does* know about (Zed, Finder, Archive
    /// Utility, …) still gets listed below, minus whichever of those is
    /// already pinned above.
    private func buildFolderOpenWithSubmenu(for url: URL) -> NSMenu {
        let submenu = NSMenu()

        let terminalAppURL = TerminalPreferenceService().bundleIdentifier()
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        submenu.addItem(pinnedFolderAppItem(
            title: terminalAppURL.map { FileManager.default.displayName(atPath: $0.path) } ?? "Terminal",
            iconURL: terminalAppURL ?? Self.defaultTerminalAppURL,
            action: #selector(handleOpenWithTerminal(_:)),
            fileURL: url
        ))
        var pinnedAppURLs = Set([terminalAppURL].compactMap { $0 })

        if let editorBundleIdentifier = EditorPreferenceService().bundleIdentifier(),
           let editorAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editorBundleIdentifier) {
            submenu.addItem(pinnedFolderAppItem(
                title: FileManager.default.displayName(atPath: editorAppURL.path),
                iconURL: editorAppURL,
                action: #selector(handleOpenWithEditor(_:)),
                fileURL: url
            ))
            pinnedAppURLs.insert(editorAppURL)
        }

        let discovered = NSWorkspace.shared.urlsForApplications(toOpen: url).filter { !pinnedAppURLs.contains($0) }
        if !discovered.isEmpty {
            submenu.addItem(.separator())
            for appURL in discovered {
                submenu.addItem(openWithMenuItem(appURL: appURL, fileURL: url))
            }
        }
        return submenu
    }

    private static let defaultTerminalAppURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    private func pinnedFolderAppItem(title: String, iconURL: URL, action: Selector, fileURL: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSWorkspace.shared.icon(forFile: iconURL.path)
        item.representedObject = fileURL
        return item
    }

    private func openWithMenuItem(appURL: URL, fileURL: URL) -> NSMenuItem {
        let name = FileManager.default.displayName(atPath: appURL.path)
        let item = NSMenuItem(title: name, action: #selector(handleOpenWith(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSWorkspace.shared.icon(forFile: appURL.path)
        item.representedObject = OpenWithSelection(appURL: appURL, fileURL: fileURL)
        return item
    }

    @objc private func handleOpenWith(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? OpenWithSelection else { return }
        openWithApp(selection.appURL, for: selection.fileURL)
    }

    @objc private func handleOpenWithTerminal(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else { return }
        openInTerminal(fileURL)
    }

    @objc private func handleOpenWithEditor(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else { return }
        openInEditor(fileURL)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookURLs[index] as NSURL
    }
}

private struct OpenWithSelection {
    let appURL: URL
    let fileURL: URL
}
