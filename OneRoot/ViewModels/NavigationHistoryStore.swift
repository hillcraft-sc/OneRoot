import Foundation
import Observation

/// App-wide, most-recent-first log of the folders the user has navigated
/// to, capped at `limit`. Shared across every tab and window — same
/// rationale as `ColumnPreferencesStore` / `FileOperationProgressCenter`:
/// browsing history belongs to the person using the app, not to one tab.
///
/// `FileListViewModel` feeds this on every successful navigation; the Go
/// menu's "Recent Locations" submenu and the General Settings pane read it.
@MainActor
@Observable
final class NavigationHistoryStore {
    static let shared = NavigationHistoryStore()

    /// Most-recent-first. Never longer than `limit`.
    private(set) var entries: [URL] = []
    private(set) var limit: Int

    private let service: NavigationHistoryService

    init(service: NavigationHistoryService = NavigationHistoryService()) {
        self.service = service
        self.limit = service.limit
        self.entries = Array(service.loadEntries().prefix(service.limit))
    }

    /// Records a visit to `url`: moves it to the front, de-duplicating any
    /// existing entry for the same folder rather than appending it again,
    /// then drops anything past `limit`. A no-op when `url` is already the
    /// most-recent entry, so re-opening the current folder, a live refresh,
    /// or a rapid back-then-forward doesn't churn the list.
    func record(_ url: URL) {
        guard entries.first != url else { return }
        var updated = entries.filter { $0 != url }
        updated.insert(url, at: 0)
        if updated.count > limit {
            updated.removeLast(updated.count - limit)
        }
        entries = updated
        service.saveEntries(entries)
    }

    func setLimit(_ newLimit: Int) {
        let clamped = NavigationHistoryService.clamp(newLimit)
        guard clamped != limit else { return }
        limit = clamped
        service.saveLimit(clamped)
        if entries.count > clamped {
            entries = Array(entries.prefix(clamped))
            service.saveEntries(entries)
        }
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        service.saveEntries([])
    }
}
