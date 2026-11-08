import Foundation
@testable import OneRoot

/// A `Theme` as GTK CSS: libadwaita's named colors for the window, the file
/// list, the bars, the sidebar and the accent, plus the colors of the
/// sidebar's icons. A theme without surfaces (the "System" look) gives no
/// CSS, so libadwaita's own colors show. No GTK here, so it is unit-tested.
enum ThemeCSS {
    static func css(for theme: Theme) -> String {
        guard let s = theme.surfaces else { return "" }
        let icons = theme.icons
        var css = ""
        func define(_ name: String, _ color: ThemeColor) { css += "@define-color \(name) \(color.hexString);\n" }

        // The window is the sidebar's tone, the file list and cards sit on the
        // background, as in the OneRoot design.
        define("window_bg_color", s.sidebar)
        define("window_fg_color", s.text)
        define("view_bg_color", s.background)
        define("view_fg_color", s.text)
        define("card_bg_color", s.background)
        define("card_fg_color", s.text)
        define("popover_bg_color", s.background)
        define("popover_fg_color", s.text)
        define("dialog_bg_color", s.sidebar)
        define("dialog_fg_color", s.text)
        define("headerbar_bg_color", s.bar)
        define("headerbar_fg_color", s.text)
        define("headerbar_backdrop_color", s.bar)
        define("headerbar_border_color", s.separator)
        define("sidebar_bg_color", s.sidebar)
        define("sidebar_fg_color", s.text)
        define("sidebar_backdrop_color", s.sidebar)
        define("sidebar_border_color", s.separator)
        define("accent_bg_color", s.accent)
        define("accent_color", s.accent)
        define("accent_fg_color", readableOn(s.accent))

        css += """
        .dim-label, .caption { color: \(s.secondaryText.hexString); opacity: 1; }
        row:selected, row:selected:hover { background-color: \(s.selection.hexString); color: \(s.selectionText.hexString); }
        .oneroot-pathbar { background-color: \(s.field.hexString); }

        """
        for (name, color) in iconColors(icons) {
            css += ".oneroot-icon-\(name) { color: \(color.hexString); }\n"
        }
        return css
    }

    /// The class a sidebar destination's icon carries, for `css(for:)`'s icon colors.
    static func iconClass(for kind: DestinationKind) -> String {
        switch kind {
        case .home, .folder: return "oneroot-icon-folder"
        case .applications: return "oneroot-icon-applications"
        case .bootVolume: return "oneroot-icon-drive"
        case .volume: return "oneroot-icon-volume"
        case .networkVolume: return "oneroot-icon-network"
        case .cloud: return "oneroot-icon-cloud"
        case .pinned, .recents, .shared: return "oneroot-icon-pinned"
        case .trash: return "oneroot-icon-trash"
        }
    }

    private static func iconColors(_ icons: ThemeIcons) -> [(String, ThemeColor)] {
        [("folder", icons.folder), ("drive", icons.drive), ("volume", icons.volume), ("network", icons.network),
         ("cloud", icons.cloud), ("pinned", icons.pinned), ("trash", icons.trash), ("applications", icons.applications)]
    }

    /// White or black, whichever reads better on `color`.
    static func readableOn(_ color: ThemeColor) -> ThemeColor {
        let white = ThemeColor(hex: 0xFFFFFF), black = ThemeColor(hex: 0x000000)
        return color.contrast(with: white) >= color.contrast(with: black) ? white : black
    }
}
