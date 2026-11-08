import Foundation
import Observation

/// Column visibility is a single app-wide preference, not per-tab state
/// (unlike sort order — see `Tab`). `.shared` is observed by every open
/// tab/window's `FileListViewModel` so toggling a column anywhere updates
/// the file list everywhere immediately, and new tabs/windows pick up
/// whatever was last chosen.
@MainActor
@Observable
final class ColumnPreferencesStore {
    static let shared = ColumnPreferencesStore()

    private(set) var visibleColumns: [FileColumn]

    private let service: ColumnPreferencesService

    init(service: ColumnPreferencesService = ColumnPreferencesService()) {
        self.service = service
        self.visibleColumns = service.load()
    }

    /// `.name` is the anchor column and can't be toggled off. Newly-shown
    /// columns are appended at the end; the user can then drag them
    /// wherever they like via `setOrder`.
    func toggle(_ column: FileColumn) {
        guard column.isRemovable else { return }
        var columns = visibleColumns
        if let index = columns.firstIndex(of: column) {
            columns.remove(at: index)
        } else {
            columns.append(column)
        }
        visibleColumns = FileColumn.normalized(columns)
        service.save(visibleColumns)
    }

    /// Persists a full explicit column order — called when the user drags
    /// a column header to reposition it.
    func setOrder(_ columns: [FileColumn]) {
        visibleColumns = FileColumn.normalized(columns)
        service.save(visibleColumns)
    }
}
