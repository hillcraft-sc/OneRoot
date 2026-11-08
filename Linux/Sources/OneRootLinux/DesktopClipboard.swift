import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The desktop's clipboard as file operations see it (`FileClipboard`).
/// Copying puts the files on it in the forms other file managers read:
/// text/uri-list, GNOME's x-special/gnome-copied-files (which also says
/// whether they were cut — Nautilus, Nemo, Thunar), KDE's cut marker, and
/// the paths as plain text. Files copied in another app are read when the
/// clipboard changes (GTK reads are asynchronous) and count as copied, the
/// safe reading when an app doesn't say.
@MainActor
final class DesktopClipboard: FileClipboard {
    private let clipboard: Clipboard
    private var cachedFiles: [URL] = []
    private var cachedIsCut = false
    private var isWriting = false
    private(set) var changeCount = 0

    init?() {
        guard let display = gdk_display_get_default(), let pointer = gdk_display_get_clipboard(display) else { return nil }
        clipboard = Clipboard(borrowing: UnsafeMutableRawPointer(pointer))
        clipboard.onChanged { [weak self] in self?.changed() }
        changed()
    }

    func files() -> (urls: [URL], isCut: Bool)? {
        cachedFiles.isEmpty ? nil : (cachedFiles, cachedIsCut)
    }

    func write(_ urls: [URL], operation: ClipboardOperation) {
        let uris = urls.map(\.absoluteString)
        var providers: [UnsafeMutablePointer<GdkContentProvider>?] = [
            Self.provider("x-special/gnome-copied-files", ([operation == .cut ? "cut" : "copy"] + uris).joined(separator: "\n")),
            Self.provider("text/uri-list", uris.joined(separator: "\r\n") + "\r\n"),
            Self.provider("text/plain;charset=utf-8", urls.map(\.path).joined(separator: "\n")),
        ]
        if operation == .cut {
            providers.append(Self.provider("application/x-kde-cutselection", "1"))
        }
        set(providers)
        cachedFiles = urls
        cachedIsCut = operation == .cut
    }

    func write(text: String) {
        set([Self.provider("text/plain;charset=utf-8", text)])
        cachedFiles = []
        cachedIsCut = false
    }

    func clear() {
        isWriting = true
        gdk_clipboard_set_content(clipboard.opaquePointer, nil)
        isWriting = false
        cachedFiles = []
        cachedIsCut = false
        changeCount += 1
    }

    private func set(_ providers: [UnsafeMutablePointer<GdkContentProvider>?]) {
        var providers = providers
        isWriting = true
        let union = providers.withUnsafeMutableBufferPointer { buffer in
            gdk_content_provider_new_union(buffer.baseAddress, gsize(buffer.count))
        }
        _ = gdk_clipboard_set_content(clipboard.opaquePointer, union)
        if let union { g_object_unref(UnsafeMutableRawPointer(union)) }
        isWriting = false
        changeCount += 1
    }

    private static func provider(_ mimeType: String, _ text: String) -> UnsafeMutablePointer<GdkContentProvider>? {
        let data = Array(text.utf8)
        let bytes = data.withUnsafeBytes { g_bytes_new($0.baseAddress, gsize($0.count)) }
        defer { g_bytes_unref(bytes) }
        return gdk_content_provider_new_for_bytes(mimeType, bytes)
    }

    /// Another app (or another OneRoot window) changed the clipboard.
    private func changed() {
        guard !isWriting else { return }
        changeCount += 1
        guard !clipboard.isLocal else { return } // ours: the cache is current
        cachedFiles = []
        cachedIsCut = false
        guard clipboard.containsFiles else { return }
        let generation = changeCount
        clipboard.readFiles { [weak self] urls in
            guard let self, generation == self.changeCount else { return }
            self.cachedFiles = urls.filter(\.isFileURL)
        }
    }
}
