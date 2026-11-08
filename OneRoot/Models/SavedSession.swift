#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation // CGRect, on Linux

/// Windows and tabs as they were at quit, reopened at next launch — see
/// `SessionService` and `SessionRestorer`. Plain paths and names rather
/// than live objects, so it stores as JSON in user defaults.
struct SavedSession: Codable, Equatable {
    /// Back to front, so reopening them in order leaves the window that
    /// was frontmost on top.
    var windows: [SavedWindow]
}

struct SavedWindow: Codable, Equatable {
    /// `nil` when it couldn't be read, or isn't on any connected screen.
    var frame: CGRect?
    var tabs: [SavedTab]
    var activeTabIndex: Int
    /// Pane visibility and sizes. `nil` in sessions saved before panes
    /// were remembered — those windows open with the default layout.
    var layout: WindowLayout? = nil
}

struct SavedTab: Codable, Equatable {
    var primary: SavedPane
    /// Present for a split tab.
    var secondary: SavedPane?
    var secondaryHasFocus: Bool
    /// Where the folder hierarchy was rooted. `nil` in older sessions; the
    /// tab then picks one from its folder (`HierarchyRootResolver`).
    var hierarchyRoot: HierarchyRoot? = nil
    /// `nil` in older sessions, which open on Details.
    var inspectorSection: InspectorSection? = nil
    var workspaceID: UUID? = nil
}

struct SavedPane: Codable, Equatable {
    var path: String
    /// A `FileColumn` raw value.
    var sortField: String
    var sortAscending: Bool
}
