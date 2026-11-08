import Foundation

/// Every theme OneRoot ships: the native macOS look in light and dark, then
/// the popular community palettes. All hex values are copied from each
/// project's own published palette (catppuccin/palette, morhetz/gruvbox,
/// nordtheme/nord, folke/tokyonight.nvim) — not recalled or approximated.
///
/// Wherever a palette's official color is too faint on that theme's own
/// surfaces (text under 4.5:1, icons and accents under 3:1), it's darkened or
/// lightened just enough to be legible, and only that color — every other
/// official color is used exactly as published. In practice that touches a
/// few accents in the three light themes, whose pastel-friendly colors are
/// meant for syntax highlighting rather than icons on a pale sidebar.
///
/// The community themes share one mapping from a palette's accents to
/// OneRoot's icon roles (see `themed`): folders take the warm accent, the
/// boot drive purple, external drives green, network yellow, cloud cyan,
/// pins blue, the Trash gray, Applications the second blue — so a theme
/// reads as one coordinated set, and the same kind of thing has the same
/// kind of color in every theme.
enum ThemeCatalog {
    /// The default choice: the OneRoot look, following macOS between
    /// `oneRootLight` and `oneRootDark`. Not itself a theme. (Its stored id
    /// is still "system" — the id Automatic always had — so anyone who
    /// never picked a theme gets the new default look.)
    static let automaticChoiceID = "system"
    /// The plain macOS look, following macOS between `nativeLight` and
    /// `nativeDark` — what Automatic meant before the OneRoot look.
    static let nativeAutomaticChoiceID = "system-native"

    /// The light and dark theme each "follow macOS" choice resolves to.
    static func automaticPair(for choiceID: String) -> (light: Theme, dark: Theme)? {
        switch choiceID {
        case automaticChoiceID: return (oneRootLight, oneRootDark)
        case nativeAutomaticChoiceID: return (nativeLight, nativeDark)
        default: return nil
        }
    }

    static func isValidChoice(_ id: String) -> Bool {
        automaticPair(for: id) != nil || theme(withID: id) != nil
    }

    static func theme(withID id: String) -> Theme? {
        all.first { $0.id == id }
    }

    /// In the order the Appearance settings list them.
    static let all: [Theme] = [oneRootLight, oneRootDark, nativeLight, nativeDark]
        + catppuccin + gruvbox + [nord] + tokyoNight

    // MARK: OneRoot (the default look)

    /// White cards on a translucent window, blue folders, a soft blue
    /// selection — the OneRoot design. Text and icon colors clear the same
    /// contrast floors as every other theme (see `ThemeTests`).
    static let oneRootLight = Theme(
        id: "oneroot-light", family: "OneRoot", name: "Light", isDark: false,
        surfaces: ThemeSurfaces(
            background: c(0xFFFFFF), sidebar: c(0xECEFF5), bar: c(0xFFFFFF), field: c(0xF1F3F7),
            selection: c(0xDCE7FB), selectionText: c(0x1B2230), separator: c(0xE2E5EB),
            text: c(0x1B2230), secondaryText: c(0x5F6878), accent: c(0x2563EB)
        ),
        icons: ThemeIcons(
            folder: c(0x3B82F6), drive: c(0x4B5563), volume: c(0x4B5563), network: c(0x4B5563),
            cloud: c(0x2563EB), pinned: c(0x2563EB), trash: c(0x4B5563), applications: c(0x4B5563),
            toolbarPrimary: c(0x1B2230), toolbarSecondary: c(0x2563EB),
            recolorsSidebarIcons: true
        ),
        usesMaterialBackdrop: true
    )

    static let oneRootDark = Theme(
        id: "oneroot-dark", family: "OneRoot", name: "Dark", isDark: true,
        surfaces: ThemeSurfaces(
            background: c(0x1F2229), sidebar: c(0x17191E), bar: c(0x1F2229), field: c(0x2A2E37),
            selection: c(0x2C3B57), selectionText: c(0xE8ECF3), separator: c(0x343944),
            text: c(0xE8ECF3), secondaryText: c(0x9AA3B2), accent: c(0x5B9BFF)
        ),
        icons: ThemeIcons(
            folder: c(0x5B9BFF), drive: c(0xB4BCC8), volume: c(0xB4BCC8), network: c(0xB4BCC8),
            cloud: c(0x5B9BFF), pinned: c(0x5B9BFF), trash: c(0xB4BCC8), applications: c(0xB4BCC8),
            toolbarPrimary: c(0xE8ECF3), toolbarSecondary: c(0x5B9BFF),
            recolorsSidebarIcons: true
        ),
        usesMaterialBackdrop: true
    )

    // MARK: Native macOS

    /// The macOS folder colors (#41): the burgundy of the app icon's leather.
    /// Light uses #58232A — the average of the lit top of that panel in the
    /// icon artwork. (#36161A, picked with a color picker, is a single dark
    /// grain of the leather; a whole folder in it looked much darker than
    /// the icon does.) That is far too dark for a dark window (about 1.3:1,
    /// the folders all but vanish), so Dark uses the same hue and saturation
    /// at higher lightness, #C46E79, which clears 3:1 on every dark ground
    /// (3.95:1 on a typical window).
    ///
    /// Before this, light used #E8554E and dark kept the original artwork's
    /// coral (#FF7069 — the `folder` asset's raw sRGB pixel bytes; sampling
    /// it through `NSColor` color-space conversion reads lighter, #FF867B,
    /// which once made the icon view's folders look washed out next to the
    /// list's).
    ///
    /// The toolbar's accent layer uses the same two colors, so the app's red
    /// is one color per theme rather than a folder red and a separate
    /// toolbar red that can drift apart.
    private static let nativeLightFolder = c(0x58232A)
    private static let nativeDarkFolder = c(0xC46E79)

    /// macOS's own colors for surfaces and text (`surfaces == nil`), with
    /// icon colors chosen to be legible on a light window — the toolbar's
    /// light-gray symbols and the sidebar's pale artwork (a nearly white
    /// Applications icon, a pale yellow network icon) vanish on white.
    static let nativeLight = Theme(
        id: "native-light", family: "macOS", name: "Light", isDark: false,
        surfaces: nil,
        icons: ThemeIcons(
            folder: nativeLightFolder, drive: c(0x8A56B8), volume: c(0x2F9E55), network: c(0xB7791F),
            cloud: c(0x1A8FA3), pinned: c(0x1F7BD8), trash: c(0x7B7B82), applications: c(0x2E6FE0),
            toolbarPrimary: c(0x48484D), toolbarSecondary: nativeLightFolder,
            recolorsSidebarIcons: true
        )
    )

    /// macOS's own colors, and OneRoot's original icon artwork as drawn,
    /// except the folder, which every theme recolors (`nativeDarkFolder`).
    static let nativeDark = Theme(
        id: "native-dark", family: "macOS", name: "Dark", isDark: true,
        surfaces: nil,
        icons: ThemeIcons(
            folder: nativeDarkFolder, drive: c(0xF89527), volume: c(0x92D5A0), network: c(0xFFE9A9),
            cloud: c(0x1AB4D0), pinned: c(0x52B9F4), trash: c(0xE0DFDE), applications: c(0x12BBF9),
            toolbarPrimary: c(0xDEDEDE), toolbarSecondary: nativeDarkFolder,
            recolorsSidebarIcons: false
        )
    )

    // MARK: Catppuccin (github.com/catppuccin/palette)

    private static let catppuccin: [Theme] = [
        themed("Catppuccin", "Latte", id: "catppuccin-latte", isDark: false, surfaces: ThemeSurfaces(
            background: c(0xEFF1F5), sidebar: c(0xE6E9EF), bar: c(0xE6E9EF), field: c(0xEFF1F5),
            selection: c(0xBCC0CC), selectionText: c(0x4C4F69), separator: c(0xCCD0DA),
            text: c(0x4C4F69), secondaryText: c(0x6C6F85), accent: c(0x8839EF)
        ), accents: Accents(
            red: c(0xD20F39), orange: c(0xFE640B), yellow: c(0xDF8E1D), green: c(0x40A02B),
            cyan: c(0x04A5E5), blue: c(0x1E66F5), indigo: c(0x7287FD), purple: c(0x8839EF), gray: c(0x7C7F93)
        )),
        themed("Catppuccin", "Frappé", id: "catppuccin-frappe", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x303446), sidebar: c(0x292C3C), bar: c(0x292C3C), field: c(0x414559),
            selection: c(0x51576D), selectionText: c(0xC6D0F5), separator: c(0x414559),
            text: c(0xC6D0F5), secondaryText: c(0xA5ADCE), accent: c(0xCA9EE6)
        ), accents: Accents(
            red: c(0xE78284), orange: c(0xEF9F76), yellow: c(0xE5C890), green: c(0xA6D189),
            cyan: c(0x99D1DB), blue: c(0x8CAAEE), indigo: c(0xBABBF1), purple: c(0xCA9EE6), gray: c(0x949CBB)
        )),
        themed("Catppuccin", "Macchiato", id: "catppuccin-macchiato", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x24273A), sidebar: c(0x1E2030), bar: c(0x1E2030), field: c(0x363A4F),
            selection: c(0x494D64), selectionText: c(0xCAD3F5), separator: c(0x363A4F),
            text: c(0xCAD3F5), secondaryText: c(0xA5ADCB), accent: c(0xC6A0F6)
        ), accents: Accents(
            red: c(0xED8796), orange: c(0xF5A97F), yellow: c(0xEED49F), green: c(0xA6DA95),
            cyan: c(0x91D7E3), blue: c(0x8AADF4), indigo: c(0xB7BDF8), purple: c(0xC6A0F6), gray: c(0x939AB7)
        )),
        themed("Catppuccin", "Mocha", id: "catppuccin-mocha", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x1E1E2E), sidebar: c(0x181825), bar: c(0x181825), field: c(0x313244),
            selection: c(0x45475A), selectionText: c(0xCDD6F4), separator: c(0x313244),
            text: c(0xCDD6F4), secondaryText: c(0xA6ADC8), accent: c(0xCBA6F7)
        ), accents: Accents(
            red: c(0xF38BA8), orange: c(0xFAB387), yellow: c(0xF9E2AF), green: c(0xA6E3A1),
            cyan: c(0x89DCEB), blue: c(0x89B4FA), indigo: c(0xB4BEFE), purple: c(0xCBA6F7), gray: c(0x9399B2)
        )),
    ]

    // MARK: Gruvbox (github.com/morhetz/gruvbox)

    private static let gruvbox: [Theme] = [
        themed("Gruvbox", "Dark", id: "gruvbox-dark", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x282828), sidebar: c(0x1D2021), bar: c(0x1D2021), field: c(0x3C3836),
            selection: c(0x504945), selectionText: c(0xEBDBB2), separator: c(0x3C3836),
            text: c(0xEBDBB2), secondaryText: c(0xA89984), accent: c(0xFABD2F)
        ), accents: Accents(
            red: c(0xFB4934), orange: c(0xFE8019), yellow: c(0xFABD2F), green: c(0xB8BB26),
            cyan: c(0x8EC07C), blue: c(0x83A598), indigo: c(0x458588), purple: c(0xD3869B), gray: c(0x928374)
        )),
        themed("Gruvbox", "Light", id: "gruvbox-light", isDark: false, surfaces: ThemeSurfaces(
            background: c(0xFBF1C7), sidebar: c(0xEBDBB2), bar: c(0xEBDBB2), field: c(0xFBF1C7),
            selection: c(0xD5C4A1), selectionText: c(0x3C3836), separator: c(0xD5C4A1),
            text: c(0x3C3836), secondaryText: c(0x7C6F64), accent: c(0xB57614)
        ), accents: Accents(
            red: c(0x9D0006), orange: c(0xAF3A03), yellow: c(0xB57614), green: c(0x79740E),
            cyan: c(0x427B58), blue: c(0x076678), indigo: c(0x458588), purple: c(0x8F3F71), gray: c(0x7C6F64)
        )),
    ]

    // MARK: Nord (nordtheme.com)

    private static let nord: Theme = {
        let nord0 = c(0x2E3440), nord1 = c(0x3B4252), nord2 = c(0x434C5E), nord3 = c(0x4C566A)
        let nord4 = c(0xD8DEE9)
        // Nord has no mid-tone for secondary text (nord3 is too dark to
        // read on nord0), so this is nord4 eased toward the background.
        let secondary = nord4.blended(with: nord0, amount: 0.35)
        return themed("Nord", "Nord", id: "nord", isDark: true, surfaces: ThemeSurfaces(
            background: nord0, sidebar: nord1, bar: nord1, field: nord0,
            selection: nord2, selectionText: nord4, separator: nord3,
            text: nord4, secondaryText: secondary, accent: c(0x88C0D0)
        ), accents: Accents(
            red: c(0xBF616A), orange: c(0xD08770), yellow: c(0xEBCB8B), green: c(0xA3BE8C),
            cyan: c(0x88C0D0), blue: c(0x81A1C1), indigo: c(0x8FBCBB), purple: c(0xB48EAD),
            gray: nord4.blended(with: nord0, amount: 0.45)
        ))
    }()

    // MARK: Tokyo Night (github.com/folke/tokyonight.nvim)

    private static let tokyoNight: [Theme] = [
        themed("Tokyo Night", "Night", id: "tokyo-night", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x1A1B26), sidebar: c(0x16161E), bar: c(0x16161E), field: c(0x292E42),
            selection: c(0x283457), selectionText: c(0xC0CAF5), separator: c(0x292E42),
            text: c(0xC0CAF5), secondaryText: c(0xA9B1D6), accent: c(0x7AA2F7)
        ), accents: Accents(
            red: c(0xF7768E), orange: c(0xFF9E64), yellow: c(0xE0AF68), green: c(0x9ECE6A),
            cyan: c(0x7DCFFF), blue: c(0x7AA2F7), indigo: c(0xBB9AF7), purple: c(0x9D7CD8), gray: c(0x737AA2)
        )),
        themed("Tokyo Night", "Storm", id: "tokyo-night-storm", isDark: true, surfaces: ThemeSurfaces(
            background: c(0x24283B), sidebar: c(0x1F2335), bar: c(0x1F2335), field: c(0x292E42),
            selection: c(0x2E3C64), selectionText: c(0xC0CAF5), separator: c(0x292E42),
            text: c(0xC0CAF5), secondaryText: c(0xA9B1D6), accent: c(0x7AA2F7)
        ), accents: Accents(
            red: c(0xF7768E), orange: c(0xFF9E64), yellow: c(0xE0AF68), green: c(0x9ECE6A),
            cyan: c(0x7DCFFF), blue: c(0x7AA2F7), indigo: c(0xBB9AF7), purple: c(0x9D7CD8), gray: c(0x737AA2)
        )),
        themed("Tokyo Night", "Day", id: "tokyo-night-day", isDark: false, surfaces: ThemeSurfaces(
            background: c(0xE1E2E7), sidebar: c(0xD0D5E3), bar: c(0xD0D5E3), field: c(0xE1E2E7),
            selection: c(0xB7C1E3), selectionText: c(0x3760BF), separator: c(0xB4B5B9),
            text: c(0x3760BF), secondaryText: c(0x6172B0), accent: c(0x2E7DE9)
        ), accents: Accents(
            red: c(0xF52A65), orange: c(0xB15C00), yellow: c(0x8C6C3E), green: c(0x587539),
            cyan: c(0x007197), blue: c(0x2E7DE9), indigo: c(0x9854F1), purple: c(0x7847BD), gray: c(0x68709A)
        )),
    ]

    // MARK: Building

    /// A palette's accents, by the role each plays in OneRoot's icons.
    private struct Accents {
        var red, orange, yellow, green, cyan, blue, indigo, purple, gray: ThemeColor
    }

    private static func themed(_ family: String, _ name: String, id: String, isDark: Bool, surfaces official: ThemeSurfaces, accents a: Accents) -> Theme {
        // Legibility floors: text 4.5:1 on every surface it sits on,
        // secondary text and graphics 3:1. See the type's doc comment.
        var s = official
        let surfaces = [s.background, s.sidebar, s.bar, s.field]
        s.text = s.text.ensuringContrast(4.5, against: surfaces)
        s.secondaryText = s.secondaryText.ensuringContrast(3.0, against: surfaces)
        s.selectionText = s.selectionText.ensuringContrast(4.5, against: [s.selection])
        let iconGrounds = [s.sidebar, s.background]
        s.accent = s.accent.ensuringContrast(3.0, against: iconGrounds)
        func icon(_ color: ThemeColor) -> ThemeColor { color.ensuringContrast(3.0, against: iconGrounds) }

        return Theme(
            id: id, family: family, name: name, isDark: isDark, surfaces: s,
            icons: ThemeIcons(
                folder: icon(a.orange), drive: icon(a.purple), volume: icon(a.green), network: icon(a.yellow),
                cloud: icon(a.cyan), pinned: icon(a.blue), trash: icon(a.gray), applications: icon(a.indigo),
                toolbarPrimary: s.text, toolbarSecondary: a.orange.ensuringContrast(3.0, against: [s.bar]),
                recolorsSidebarIcons: true
            )
        )
    }

    private static func c(_ hex: UInt32) -> ThemeColor { ThemeColor(hex: hex) }
}
