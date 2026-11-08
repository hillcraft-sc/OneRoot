import AppKit

extension NSPasteboard.PasteboardType {
    /// Internal-only — never written to a real file or shared outside this
    /// process, so a raw reverse-DNS string is enough; no need to register
    /// it as a `UTType` in Info.plist the way an actual document type
    /// would be.
    static let oneRootTab = NSPasteboard.PasteboardType("com.oneroot.tab")
}

/// In-memory handoff for dragging a tab between two `TabBarView`s —
/// including two different windows'. `NSPasteboard` can only carry
/// serializable data, not a live `Tab`/`WindowViewModel` reference, so the
/// pasteboard item carries just a token; the actual objects are looked up
/// here by whichever drop destination (or the drag source itself, on a
/// tear-off) ends up handling it.
@MainActor
final class TabDragRegistry {
    static let shared = TabDragRegistry()

    private var inFlight: [UUID: (tab: Tab, source: WindowViewModel)] = [:]

    private init() {}

    func begin(_ tab: Tab, from source: WindowViewModel) -> UUID {
        let token = UUID()
        inFlight[token] = (tab, source)
        return token
    }

    func lookup(_ token: UUID) -> (tab: Tab, source: WindowViewModel)? {
        inFlight[token]
    }

    func end(_ token: UUID) {
        inFlight.removeValue(forKey: token)
    }

    /// Shared by every drop destination a tab can land on (another tab, to
    /// reorder or insert-before/after; the trailing catch-all past the
    /// last tab) — looks the drag up by its pasteboard token and either
    /// reorders it in place or moves it over from its source window.
    @discardableResult
    func handleDrop(_ sender: NSDraggingInfo, into destinationViewModel: WindowViewModel, at index: Int) -> Bool {
        guard let tokenString = sender.draggingPasteboard.string(forType: .oneRootTab),
              let token = UUID(uuidString: tokenString),
              let (draggedTab, sourceViewModel) = lookup(token) else { return false }
        end(token)
        if sourceViewModel === destinationViewModel {
            destinationViewModel.moveTab(draggedTab, to: index)
        } else {
            sourceViewModel.detachTab(draggedTab)
            destinationViewModel.insertTab(draggedTab, at: index)
        }
        return true
    }
}
