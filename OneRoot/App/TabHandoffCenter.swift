import Foundation // CGPoint and CGRect, on Linux too

/// Carries a torn-off tab from its source window to the brand-new window
/// `openWindow(id:value:)` spins up for it. `openWindow`'s value payload
/// has to be `Codable & Hashable`, and `Tab` (it owns a live
/// `FileListViewModel`) is neither — nor should it be, just to satisfy a
/// one-shot handoff. So the value that actually travels through
/// `openWindow` is a disposable `UUID` token; the live `Tab` and the
/// screen point to open the new window at are held here in memory and
/// looked up by that token once the new window's view appears.
@MainActor
final class TabHandoffCenter {
    static let shared = TabHandoffCenter()

    private var pending: [UUID: (tab: Tab, screenPoint: CGPoint)] = [:]

    private init() {}

    /// Where to put a new window opened by the keyboard shortcut (rather than
    /// a drag): its top-left a little down and right of `frame`'s, so it
    /// doesn't land exactly on top of the window it came from. Returned as the
    /// handoff's `screenPoint`, which the new window turns back into its
    /// top-left (see `MainWindowView`'s `pendingWindowOrigin`: x − 80, y + 20).
    static func cascadePoint(from frame: CGRect) -> CGPoint {
        let offset: CGFloat = 30
        return CGPoint(x: frame.minX + offset + 80, y: frame.maxY - offset - 20)
    }

    func store(_ tab: Tab, screenPoint: CGPoint) -> UUID {
        let token = UUID()
        pending[token] = (tab, screenPoint)
        return token
    }

    func take(_ token: UUID) -> (tab: Tab, screenPoint: CGPoint)? {
        defer { pending.removeValue(forKey: token) }
        return pending[token]
    }
}
