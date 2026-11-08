import Foundation

/// The colors a theme gives OneRoot's own surfaces and text. A theme without
/// these (`Theme.surfaces == nil`) leaves them to macOS: the system's
/// dynamic colors, which follow light/dark by themselves.
struct ThemeSurfaces: Equatable {
    /// The file list, icon grid, and preview pane.
    var background: ThemeColor
    var sidebar: ThemeColor
    /// The tab strip, both toolbars, the status bar, and column headers.
    var bar: ThemeColor
    /// Text fields: search, address bar, breadcrumbs.
    var field: ThemeColor
    /// A selected row or icon.
    var selection: ThemeColor
    /// Text on `selection`. The same as `text` in the bundled themes, whose
    /// selections are a quiet tint rather than a solid accent.
    var selectionText: ThemeColor
    var separator: ThemeColor
    var text: ThemeColor
    var secondaryText: ThemeColor
    /// Focus rings, the active tab, sliders, links, the focused pane's
    /// header.
    var accent: ThemeColor
}

/// The colors of OneRoot's own icons: the sidebar's, the icon view's folder,
/// and the toolbar's two-tone symbols. File-type icons from macOS (a PDF's,
/// a photo's) aren't ours to recolor.
struct ThemeIcons: Equatable {
    var folder: ThemeColor
    /// The boot volume.
    var drive: ThemeColor
    /// External drives and mounted disk images.
    var volume: ThemeColor
    var network: ThemeColor
    var cloud: ThemeColor
    var pinned: ThemeColor
    var trash: ThemeColor
    var applications: ThemeColor
    /// A toolbar symbol's main layer, and its accent layer. No longer
    /// drawn — the toolbar went monochrome (`BarButtonStyle`) — but kept in
    /// each theme's definition in case a theme ever wants them back.
    var toolbarPrimary: ThemeColor
    var toolbarSecondary: ThemeColor
    /// `false` keeps the sidebar's original multi-color artwork as drawn;
    /// every other theme recolors it from the colors above.
    var recolorsSidebarIcons: Bool
}

struct Theme: Identifiable, Equatable {
    /// Stable, stored in preferences — never change one.
    let id: String
    /// "Catppuccin", "Gruvbox", … — the group it's listed under.
    let family: String
    /// "Mocha", "Dark", … — its name within the family.
    let name: String
    /// Whether the window should use macOS's dark appearance for everything
    /// the theme doesn't paint itself (scrollbars, text cursors, menus,
    /// system controls).
    let isDark: Bool
    let surfaces: ThemeSurfaces?
    let icons: ThemeIcons
    /// The window shows macOS's translucent material behind the sidebar and
    /// around the content cards, instead of a flat surface color.
    var usesMaterialBackdrop = false

    var displayName: String { family == name ? name : "\(family) \(name)" }
}
