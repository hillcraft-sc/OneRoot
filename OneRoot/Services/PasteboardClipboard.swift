#if os(macOS)
import AppKit

/// The Mac's clipboard (`NSPasteboard`) as a `FileClipboard`. Files go on
/// as file URLs, so they paste into Finder and other apps too, with a
/// private marker saying whether OneRoot cut them — so Cut in the folder
/// tree and Paste in the list (or the other way round) work together.
@MainActor
final class PasteboardClipboard: FileClipboard {
    static let operationType = NSPasteboard.PasteboardType("com.oneroot.pasteboard.operation")

    let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func files() -> (urls: [URL], isCut: Bool)? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else { return nil }
        return (urls, pasteboard.string(forType: Self.operationType) == ClipboardOperation.cut.rawValue)
    }

    func write(_ urls: [URL], operation: ClipboardOperation) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(operation.rawValue, forType: Self.operationType)
    }

    func write(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clear() {
        pasteboard.clearContents()
    }

    var changeCount: Int { pasteboard.changeCount }
}
#endif
