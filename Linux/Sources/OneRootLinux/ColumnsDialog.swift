import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Columns…: a switch per column, the keyboard-reachable twin of the
/// header's right-click menu. Choices go to the shared
/// `ColumnPreferencesStore`, so every tab and window follows.
@MainActor
enum ColumnsDialog {
    static func present(for pane: FileListViewModel, over parent: Widget) {
        let dialog = PreferencesDialog()
        dialog.title = "Columns"
        dialog.contentWidth = 420
        dialog.contentHeight = 520
        let page = PreferencesPage()
        let group = PreferencesGroup()
        group.title = "Show in the file list"
        group.description = "Name is always shown. Drag a column header to reorder."
        for field in FileColumn.allCases where field.isRemovable && field != .location {
            let row = SwitchRow()
            row.title = field.title
            row.active = pane.visibleColumns.contains(field)
            row.onNotify(.custom("active")) { [row] in
                if row.active != pane.visibleColumns.contains(field) { pane.toggleColumn(field) }
            }
            group.add(row)
        }
        page.add(group)
        dialog.add(page)
        dialog.present(parent)
    }
}
