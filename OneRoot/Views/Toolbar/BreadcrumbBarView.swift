import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The address bar when it isn't being typed in: the current path as
/// clickable segments, Explorer-style — "Macintosh HD › Users › eric".
/// Clicking a segment goes there; each "›" drops down that folder's
/// subfolders; clicking the empty space after the last segment switches to
/// typing (see `AddressBarView`). When the path is too long to fit, leading
/// segments collapse into a "…" menu. Files dropped on a segment move
/// there (⌥ to copy), same as dropping on a folder in the list or sidebar.
struct BreadcrumbBarView: View {
    let segments: [BreadcrumbSegment]
    let onNavigate: (URL) -> Void
    let onOpenInNewTab: (URL) -> Void
    let onBeginEditing: () -> Void
    let onCopyPath: () -> Void
    /// (dropped URLs, destination folder, move rather than copy)
    let onDrop: ([URL], URL, Bool) -> Void

    private let fileSystemService = FileSystemService()
    @Environment(\.appTheme) private var theme
    /// Shows a checkmark on the copy button for a moment after copying.
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 0) {
            // Tries showing every segment first, then hiding more and more
            // of the leading ones, and uses the first row that fits.
            ViewThatFits(in: .horizontal) {
                ForEach(0..<max(segments.count, 1), id: \.self) { hiddenCount in
                    row(hidingFirst: hiddenCount)
                }
            }
            .layoutPriority(1)

            // The rest of the bar: click to type a path.
            Color.clear
                .frame(minWidth: 24, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBeginEditing)
                .accessibilityHidden(true)

            // Always-visible ways to type a path or copy it, so neither
            // depends on knowing the empty space is clickable.
            trailingButton("pencil", label: "Edit Path", help: "Type a path (⇧⌘G)", action: onBeginEditing)
            trailingButton(didCopy ? "checkmark" : "doc.on.doc", label: "Copy Path", help: "Copy this folder's full path (⌥⌘C)") {
                onCopyPath()
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.fieldColor))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.separatorColor))
        .help("Click a folder to go there, or click the empty space to type a path (⇧⌘G)")
    }

    private func trailingButton(_ systemImage: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    private func row(hidingFirst hiddenCount: Int) -> some View {
        HStack(spacing: 0) {
            if hiddenCount > 0 {
                Menu {
                    ForEach(Array(segments.prefix(hiddenCount).reversed().enumerated()), id: \.offset) { _, segment in
                        Button(segment.name) { onNavigate(segment.url) }
                    }
                } label: {
                    Text("\u{2026}")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 4)
                .accessibilityLabel("Earlier folders")
            }
            ForEach(Array(segments.enumerated().dropFirst(hiddenCount)), id: \.offset) { index, segment in
                SegmentButton(title: segment.name, isCurrent: index == segments.count - 1, folder: segment.url, onDrop: onDrop) {
                    onNavigate(segment.url)
                }
                .contextMenu {
                    Button("Open in New Tab") { onOpenInNewTab(segment.url) }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(segment.url.path, forType: .string)
                    }
                }
                ChevronButton(folderName: segment.name) { showSubfolderMenu(of: segment.url) }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// An `NSMenu` built on click rather than a SwiftUI `Menu`: a `Menu`'s
    /// items are built with the view, which would mean listing every
    /// segment's subfolders on every navigation just in case.
    private func showSubfolderMenu(of folder: URL) {
        let location = NSEvent.mouseLocation
        Task {
            let names = await fileSystemService.suggestFolders(in: folder)
            let target = MenuActionTarget(onNavigate)
            let menu = NSMenu()
            if names.isEmpty {
                let empty = NSMenuItem(title: "No Subfolders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for name in names {
                let url = folder.appendingPathComponent(name, isDirectory: true)
                let item = NSMenuItem(title: name, action: #selector(MenuActionTarget.choose(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = url
                // Its own copy: the themed bitmap is shared, and resized here.
                let icon = (ThemedIcons.icon(for: url, isFolder: true, theme: theme).copy() as? NSImage) ?? NSImage()
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
            // `popUp` runs the menu modally, so `target` outlives it.
            withExtendedLifetime(target) {
                _ = menu.popUp(positioning: nil, at: location, in: nil)
            }
        }
    }
}

/// One path segment: plain text that highlights on hover, like Explorer's,
/// and accepts dropped files.
private struct SegmentButton: View {
    let title: String
    let isCurrent: Bool
    let folder: URL
    let onDrop: ([URL], URL, Bool) -> Void
    let action: () -> Void
    @State private var isHovered = false
    @State private var isDropTarget = false
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isCurrent ? .medium : .regular)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(background))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDrop(of: [.fileURL], delegate: SegmentDropDelegate(folder: folder, isTargeted: $isDropTarget, onDrop: onDrop))
        .accessibilityLabel(isCurrent ? "\(title), current folder" : "Go to \(title)")
    }

    private var background: Color {
        if isDropTarget { return theme.accentColor.opacity(0.35) }
        return isHovered ? Color.primary.opacity(0.1) : .clear
    }
}

/// SwiftUI's drop API doesn't expose the drag's allowed operations the way
/// `NSDraggingInfo` does for the list and sidebar, so ⌥ is read directly:
/// held means copy, otherwise move — which is what those other drop
/// targets end up doing for a normal drag (⌥ is what takes `.move` out of
/// the operation mask they check).
private struct SegmentDropDelegate: DropDelegate {
    let folder: URL
    @Binding var isTargeted: Bool
    let onDrop: ([URL], URL, Bool) -> Void

    private var isCopy: Bool { NSEvent.modifierFlags.contains(.option) }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isCopy ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let move = !isCopy
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            // Same guard as the list/sidebar: no folder into itself.
            guard !urls.isEmpty, isValidDropTarget(folder, for: urls) else { return }
            onDrop(urls, folder, move)
        }
        return true
    }
}

private struct ChevronButton: View {
    let folderName: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(isHovered ? Color.primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Subfolders")
        .accessibilityLabel("Subfolders of \(folderName)")
    }
}

/// `NSMenuItem` needs an Objective-C target/action; this forwards to a closure.
private final class MenuActionTarget: NSObject {
    private let handler: (URL) -> Void

    init(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        handler(url)
    }
}
