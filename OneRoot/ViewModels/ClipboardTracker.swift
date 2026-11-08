import Foundation
import Observation

/// What OneRoot itself last put on the clipboard — for the command bar's
/// Paste chip. The clipboard is shared by every app and outlives OneRoot,
/// so it can hold files nobody copied *here* (or copied long ago); the chip
/// should only offer what you just copied or cut in OneRoot. Remembered in
/// memory only: a relaunch, or anything else writing to the clipboard
/// (another app, or a Cut being pasted), forgets it.
@MainActor
@Observable
final class ClipboardTracker {
    static let shared = ClipboardTracker()

    struct Pending: Equatable {
        let count: Int
        let operation: ClipboardOperation
    }

    private(set) var pending: Pending?

    @ObservationIgnored private let clipboard: FileClipboard
    /// The clipboard's change count right after OneRoot wrote to it.
    @ObservationIgnored private var recordedChangeCount: Int?

    init(clipboard: FileClipboard? = nil) {
        self.clipboard = clipboard ?? Platform.clipboard
    }

    /// Call right after writing `count` items to the clipboard.
    func record(count: Int, operation: ClipboardOperation) {
        recordedChangeCount = clipboard.changeCount
        pending = Pending(count: count, operation: operation)
    }

    /// Forgets the record once anything else has changed the clipboard.
    func refresh() {
        guard pending != nil, clipboard.changeCount != recordedChangeCount else { return }
        pending = nil
        recordedChangeCount = nil
    }
}
