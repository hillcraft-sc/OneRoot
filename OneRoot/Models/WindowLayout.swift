import Foundation

/// A tool the bottom contextual workspace can show — one at a time. Only
/// File Operations so far; Visualize and Quick Actions join later. (Dual
/// Pane was tried here and moved back beside the file list.)
enum WorkspaceTool: String, Codable, CaseIterable {
    case fileOperations

    var title: String {
        switch self {
        case .fileOperations: return "File Operations"
        }
    }

    var systemImage: String {
        switch self {
        case .fileOperations: return "arrow.left.arrow.right.square"
        }
    }
}

/// Which of a window's panes are shown, and how big they are. Saved with
/// the session per window; the last-changed layout also seeds new windows
/// (see `WindowLayoutService`).
///
/// The `shows…` flags are the user's choice. What's actually on screen can
/// be less when the window is too narrow for everything — see `fitted(to:)`
/// — without the choice itself being forgotten.
struct WindowLayout: Codable, Equatable {
    /// Bumped when the defaults change enough that layouts saved before
    /// shouldn't carry over — those decode as the new defaults instead.
    /// 2: the OneRoot layout (Inspector and tool cards showing).
    /// 3: tool cards hidden by default — a layout from 2 is kept, with them
    ///    hidden (Quick Actions moved into the Context Bar).
    static let currentVersion = 3
    var version = WindowLayout.currentVersion

    // The OneRoot layout: every pane showing, as in the design.
    var showsDestinations = true
    var showsHierarchy = true
    var showsInspector = true
    var destinationsWidth: Double = 210
    var hierarchyWidth: Double = 230
    var inspectorWidth: Double = 300
    var isWorkspaceExpanded = false
    var workspaceHeight: Double = 180
    var workspaceTool: WorkspaceTool = .fileOperations

    init() {}

    /// Any key missing (a layout saved by an older build) keeps its default
    /// instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WindowLayout()
        let version = try? container.decodeIfPresent(Int.self, forKey: .version)
        guard version == Self.currentVersion || version == 2 else {
            self = defaults
            return
        }
        showsDestinations = try container.decodeIfPresent(Bool.self, forKey: .showsDestinations) ?? defaults.showsDestinations
        showsHierarchy = try container.decodeIfPresent(Bool.self, forKey: .showsHierarchy) ?? defaults.showsHierarchy
        showsInspector = try container.decodeIfPresent(Bool.self, forKey: .showsInspector) ?? defaults.showsInspector
        destinationsWidth = try container.decodeIfPresent(Double.self, forKey: .destinationsWidth) ?? defaults.destinationsWidth
        hierarchyWidth = try container.decodeIfPresent(Double.self, forKey: .hierarchyWidth) ?? defaults.hierarchyWidth
        inspectorWidth = try container.decodeIfPresent(Double.self, forKey: .inspectorWidth) ?? defaults.inspectorWidth
        isWorkspaceExpanded = try container.decodeIfPresent(Bool.self, forKey: .isWorkspaceExpanded) ?? defaults.isWorkspaceExpanded
        workspaceHeight = try container.decodeIfPresent(Double.self, forKey: .workspaceHeight) ?? defaults.workspaceHeight
        workspaceTool = (try? container.decodeIfPresent(WorkspaceTool.self, forKey: .workspaceTool)) ?? defaults.workspaceTool
        if version == 2 { isWorkspaceExpanded = false }
    }

    static let destinationsWidthRange: ClosedRange<Double> = 160...320
    static let hierarchyWidthRange: ClosedRange<Double> = 160...420
    static let inspectorWidthRange: ClosedRange<Double> = 220...520
    static let workspaceHeightRange: ClosedRange<Double> = 140...480
    /// The file list never gets narrower than this.
    static let minimumListWidth: Double = 360

    /// Panes actually shown in a window `width` points wide. When the
    /// chosen panes don't all fit next to a usable file list, the Inspector
    /// gives way first, then the hierarchy, then the destinations sidebar.
    func fitted(to width: Double) -> WindowLayout {
        var fitted = self
        func required() -> Double {
            Self.minimumListWidth
                + (fitted.showsDestinations ? Self.destinationsWidthRange.lowerBound : 0)
                + (fitted.showsHierarchy ? Self.hierarchyWidthRange.lowerBound : 0)
                + (fitted.showsInspector ? Self.inspectorWidthRange.lowerBound : 0)
        }
        if required() > width { fitted.showsInspector = false }
        if required() > width { fitted.showsHierarchy = false }
        if required() > width { fitted.showsDestinations = false }
        return fitted
    }

    /// Widths/height pulled back into range — a stored value from an older
    /// build, or a hand-edited default, can't produce an unusable pane.
    var clamped: WindowLayout {
        var layout = self
        layout.destinationsWidth = destinationsWidth.clamped(to: Self.destinationsWidthRange)
        layout.hierarchyWidth = hierarchyWidth.clamped(to: Self.hierarchyWidthRange)
        layout.inspectorWidth = inspectorWidth.clamped(to: Self.inspectorWidthRange)
        layout.workspaceHeight = workspaceHeight.clamped(to: Self.workspaceHeightRange)
        return layout
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
