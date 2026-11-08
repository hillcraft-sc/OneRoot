import Foundation

/// Whether files on the clipboard were copied or cut in OneRoot.
enum ClipboardOperation: String, Sendable {
    case copy, cut
}

/// The clipboard as file operations see it: files (and whether they were
/// cut), or text. The system's on the Mac (`PasteboardClipboard`); on
/// Linux, `MemoryClipboard` until the Linux app supplies the desktop's.
@MainActor
protocol FileClipboard: AnyObject {
    /// The files on the clipboard, and whether OneRoot cut them; `nil`
    /// when it holds no files.
    func files() -> (urls: [URL], isCut: Bool)?
    func write(_ urls: [URL], operation: ClipboardOperation)
    func write(text: String)
    func clear()
    /// Goes up whenever anything — any app — changes the clipboard.
    var changeCount: Int { get }
}

extension FileClipboard {
    var hasFiles: Bool { files() != nil }
}

/// A clipboard that lives in this process only — for tests, and for Linux
/// until the app there plugs in the desktop's clipboard (#82).
@MainActor
final class MemoryClipboard: FileClipboard {
    private var urls: [URL] = []
    private var text: String?
    private var operation: ClipboardOperation = .copy
    private(set) var changeCount = 0

    init() {}

    func files() -> (urls: [URL], isCut: Bool)? {
        urls.isEmpty ? nil : (urls, operation == .cut)
    }

    func write(_ urls: [URL], operation: ClipboardOperation) {
        self.urls = urls
        self.operation = operation
        text = nil
        changeCount += 1
    }

    func write(text: String) {
        urls = []
        self.text = text
        changeCount += 1
    }

    /// The text last written — what a paste into a text field would get.
    var string: String? { text }

    func clear() {
        urls = []
        text = nil
        changeCount += 1
    }
}
