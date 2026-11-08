import AppKit
import Combine
import QuickLookThumbnailing
import QuickLookUI

/// The icon view's collection view. Hands keys, edit actions, and the
/// context menu to the shared `FileItemActions` exactly as `FileTableView`
/// does, so both views behave the same.
final class FileCollectionView: NSCollectionView {
    weak var actions: FileItemActions?
    var onDoubleClick: ((IndexPath) -> Void)?
    /// Selection set from code (a right-click on an unselected item) doesn't
    /// reach the delegate, so the controller hears about it here.
    var onProgrammaticSelectionChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if actions?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // Deferred: focus can move mid SwiftUI update (e.g. Quick Look making
        // this first responder), and `onFocus` publishes on the `Tab`.
        if became, let onFocus = actions?.onFocus {
            DispatchQueue.main.async { onFocus() }
        }
        return became
    }

    @objc func copy(_ sender: Any?) { actions?.handleCopy() }
    @objc func cut(_ sender: Any?) { actions?.handleCut() }
    @objc func paste(_ sender: Any?) { actions?.handlePaste() }

    // Edit ▸ Undo/Redo act on file operations while the grid has focus —
    // see `FileUndoCenter`.
    @objc func undo(_ sender: Any?) { FileUndoCenter.shared.undo() }
    @objc func redo(_ sender: Any?) { FileUndoCenter.shared.redo() }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // NSCollectionView has no double-click action of its own.
        guard event.clickCount == 2,
              let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return }
        onDoubleClick?(indexPath)
    }

    /// Driven by hand for the same reason as `FileTableView.rightMouseDown`:
    /// AppKit's automatic `view.menu` popup doesn't reliably show here.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clicked = indexPathForItem(at: point)
        actions?.isBackgroundRightClick = clicked == nil
        if let clicked, !selectionIndexPaths.contains(clicked) {
            selectionIndexPaths = [clicked]
            onProgrammaticSelectionChange?()
        }
        guard let menu else {
            super.rightMouseDown(with: event)
            return
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = actions
        panel.delegate = actions
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension FileCollectionView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        FileUndoCenter.shared.validate(menuItem) ?? true
    }
}

/// Owns the icon grid (`NSCollectionView`): layout, thumbnails, selection,
/// and drag and drop. Everything you can do to the selection lives in the
/// shared `actions`, same as the list — see `FileTableController`.
@MainActor
final class FileIconController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collectionView: FileCollectionView
    let actions = FileItemActions()
    var onSelectionChange: (([FileNode]) -> Void)?
    /// Last `FileListViewModel.quickLookTrigger` value already acted on.
    var lastHandledQuickLookTrigger = 0

    /// Reassigned on every live refresh, so — like the list — the selection
    /// is carried across the reload by URL rather than lost.
    var items: [FileNode] = [] {
        willSet { selectionURLsBeforeReload = Set(selectedNodes.map(\.url)) }
        didSet {
            let before = collectionView.selectionIndexPaths
            collectionView.reloadData()
            restoreSelection()
            // Set in code, so the delegate doesn't report it — tell the view
            // model ourselves when it changed (a new folder, items trashed).
            if collectionView.selectionIndexPaths != before { reportSelection() }
        }
    }
    private var selectionURLsBeforeReload: Set<URL> = []

    /// Edge length of the icon/thumbnail square, in points.
    var iconSize: CGFloat = 96 {
        didSet {
            guard oldValue != iconSize else { return }
            layout.itemSize = Self.itemSize(for: iconSize)
            collectionView.reloadData()
            restoreSelection(Set(selectedNodes.map(\.url)))
        }
    }

    private let layout = NSCollectionViewFlowLayout()
    private let thumbnails = ThumbnailCache()

    /// Follows `ThemeStore`; see `apply(_:)`.
    private var theme = ThemeStore.shared.current
    private var themeWatch: ObservationWatch?

    override init() {
        collectionView = FileCollectionView()
        super.init()

        layout.itemSize = Self.itemSize(for: iconSize)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [theme.listBackgroundNSColor]
        collectionView.register(FileIconItem.self, forItemWithIdentifier: FileIconItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.every, forLocal: false)

        collectionView.actions = actions
        actions.hostView = collectionView
        actions.selectionProvider = { [weak self] in self?.selectedNodes ?? [] }
        collectionView.onDoubleClick = { [weak self] indexPath in
            guard let self, let node = self.node(at: indexPath) else { return }
            self.actions.openOnDoubleClick(node)
        }
        collectionView.onProgrammaticSelectionChange = { [weak self] in self?.reportSelection() }

        let menu = NSMenu()
        menu.delegate = actions
        collectionView.menu = menu

        themeWatch = ObservationWatch.watch({ ThemeStore.shared.current }) { [weak self] theme in
            self?.apply(theme)
        }
    }

    /// Recolors the grid: background, and every visible item's name, folder
    /// and selection colors. Items are reloaded in place (not `reloadData`),
    /// so the selection carries over.
    private func apply(_ theme: Theme) {
        self.theme = theme
        collectionView.backgroundColors = [theme.listBackgroundNSColor]
        let visible = collectionView.indexPathsForVisibleItems()
        if !visible.isEmpty {
            collectionView.reloadItems(at: visible)
        }
    }

    private static func itemSize(for iconSize: CGFloat) -> NSSize {
        // Room for the icon plus two lines of name underneath.
        NSSize(width: max(iconSize + 36, 90), height: iconSize + 46)
    }

    private var selectedNodes: [FileNode] {
        collectionView.selectionIndexPaths.sorted().compactMap(node(at:))
    }

    private func node(at indexPath: IndexPath) -> FileNode? {
        items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
    }

    /// Set once the first `select(_:)` has run — see `FileListView`.
    var didRestoreInitialSelection = false
    /// Last `FileListViewModel.selectionRequest` acted on.
    var lastHandledSelectionRequest = 0
    /// Last `FileListViewModel.clearSelectionTrigger` acted on.
    var lastHandledClearSelectionTrigger = 0

    func clearSelection() {
        collectionView.deselectAll(nil)
        reportSelection()
    }

    /// See `FileTableController.select(_:)`.
    func select(_ urls: Set<URL>) {
        restoreSelection(urls)
        if let first = collectionView.selectionIndexPaths.min() {
            collectionView.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
        }
        reportSelection()
    }

    private func restoreSelection(_ urls: Set<URL>? = nil) {
        let wanted = urls ?? selectionURLsBeforeReload
        let indexPaths = items.enumerated()
            .filter { wanted.contains($0.element.url) }
            .map { IndexPath(item: $0.offset, section: 0) }
        collectionView.selectionIndexPaths = Set(indexPaths)
    }

    /// Deferred a tick, like `FileTableController.tableViewSelectionDidChange`:
    /// selection can change mid SwiftUI update (a reload from `updateNSView`),
    /// and publishing on the view model then is what SwiftUI won't tolerate.
    private func reportSelection() {
        let nodes = selectedNodes
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChange?(nodes)
        }
    }

    // MARK: NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FileIconItem.identifier, for: indexPath)
        guard let iconItem = item as? FileIconItem, let node = node(at: indexPath) else { return item }
        iconItem.configure(name: node.name, url: node.url, iconSize: iconSize, theme: theme)
        iconItem.setImage(thumbnails.icon(for: node, size: iconSize, folderColor: theme.icons.folder))
        // Real thumbnails for documents and media; folders and apps keep
        // their icons, which is what their "thumbnail" would be anyway.
        if !node.isDirectory {
            let scale = collectionView.window?.backingScaleFactor ?? 2
            thumbnails.thumbnail(for: node, size: iconSize, scale: scale) { [weak iconItem] image in
                guard let iconItem, iconItem.url == node.url else { return } // cell reused meanwhile
                iconItem.setImage(image)
            }
        }
        return iconItem
    }

    // MARK: NSCollectionViewDelegate — selection

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection()
    }

    // MARK: Drag source

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        node(at: indexPath)?.url as NSURL?
    }

    // MARK: Drop destination

    /// A folder item under the pointer, or `nil` for "the folder being shown".
    private func dropTargetNode(_ indexPath: IndexPath, _ operation: NSCollectionView.DropOperation) -> FileNode? {
        guard operation == .on, let node = node(at: indexPath), node.isDirectory, !node.isPackage else { return nil }
        return node
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard let urls = draggingInfo.draggedFileURLs else { return [] }
        if let target = dropTargetNode(proposedDropIndexPath.pointee as IndexPath, proposedDropOperation.pointee) {
            guard isValidDropTarget(target.url, for: urls) else { return [] }
        } else {
            // Not on a folder: the drop goes into the folder being shown,
            // so highlight the whole grid rather than a gap between items.
            proposedDropOperation.pointee = .before
            proposedDropIndexPath.pointee = NSIndexPath(forItem: 0, inSection: 0)
        }
        return DropActionMenu.operation(for: draggingInfo)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let urls = draggingInfo.draggedFileURLs else { return false }
        let target = dropTargetNode(indexPath, dropOperation)
        if let target, !isValidDropTarget(target.url, for: urls) { return false }
        actions.drop(urls, on: target, info: draggingInfo)
        return true
    }
}

/// One icon in the grid: the icon/thumbnail with the name underneath,
/// Finder-style selection (a soft square behind the icon, the name in a
/// highlighted capsule).
final class FileIconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileIconItem")

    private(set) var url: URL?
    private let iconView = NSImageView()
    private let iconBackground = NSView()
    private let nameField = NSTextField(wrappingLabelWithString: "")
    private var iconSizeConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        view = NSView()

        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 6
        iconView.imageScaling = .scaleProportionallyUpOrDown

        nameField.alignment = .center
        nameField.maximumNumberOfLines = 2
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        nameField.wantsLayer = true
        nameField.layer?.cornerRadius = 4

        for subview in [iconBackground, iconView, nameField] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconBackground.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -4),
            iconBackground.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            iconBackground.leadingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -4),
            iconBackground.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            nameField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            nameField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameField.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -6),
        ])
    }

    private var theme = ThemeCatalog.nativeDark

    func configure(name: String, url: URL, iconSize: CGFloat, theme: Theme) {
        self.url = url
        self.theme = theme
        nameField.stringValue = name
        NSLayoutConstraint.deactivate(iconSizeConstraints)
        iconSizeConstraints = [
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
        ]
        NSLayoutConstraint.activate(iconSizeConstraints)
        nameField.preferredMaxLayoutWidth = max(iconSize + 30, 84)
        updateSelectionAppearance()
    }

    func setImage(_ image: NSImage?) {
        iconView.image = image
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelectionAppearance() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        url = nil
        iconView.image = nil
    }

    private func updateSelectionAppearance() {
        let selected = isSelected || highlightState == .forSelection
        guard let selection = theme.selectionNSColor, let selectionText = theme.selectionTextNSColor else {
            // Native: the system's own selection colors.
            iconBackground.layer?.backgroundColor = selected ? NSColor.quaternaryLabelColor.cgColor : nil
            nameField.layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.cgColor : nil
            nameField.textColor = selected ? .alternateSelectedControlTextColor : theme.textNSColor
            return
        }
        iconBackground.layer?.backgroundColor = selected ? selection.withAlphaComponent(0.6).cgColor : nil
        nameField.layer?.backgroundColor = selected ? selection.cgColor : nil
        nameField.textColor = selected ? selectionText : theme.textNSColor
    }
}

/// File icons and Quick Look thumbnails, cached so scrolling back over
/// items (or a live refresh reloading the grid) doesn't regenerate them.
@MainActor
private final class ThumbnailCache {
    private let icons = NSCache<NSString, NSImage>()
    private let thumbnails = NSCache<NSString, NSImage>()

    init() {
        thumbnails.countLimit = 2_000
    }

    /// The item's icon — immediate, shown until (or instead of) a real
    /// thumbnail. Plain folders get OneRoot's own folder (see
    /// `themedFolderIcon`) rather than Finder's blue one, matching the list
    /// and sidebar; everything else gets its system icon.
    func icon(for node: FileNode, size: CGFloat, folderColor: ThemeColor) -> NSImage {
        if node.isDirectory && !node.isPackage {
            return ThemedIcons.folder(size: size, color: folderColor)
        }
        let key = node.url.path as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    /// Calls `completion` on the main actor with a content thumbnail (an
    /// image's pixels, a document's first page) once one exists — not at
    /// all if Quick Look can only offer an icon. Keyed by modification date
    /// too, so an edited file gets a fresh thumbnail.
    func thumbnail(for node: FileNode, size: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        let modified = node.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        let keyString = "\(node.url.path)|\(Int(size))|\(modified)"
        if let cached = thumbnails.object(forKey: keyString as NSString) {
            completion(cached)
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: node.url,
            // Whole points: Quick Look rounds a fractional size itself and
            // logs a warning for every request that has one.
            size: CGSize(width: size.rounded(), height: size.rounded()),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.thumbnails.setObject(image, forKey: keyString as NSString)
                    completion(image)
                }
            }
        }
    }
}
