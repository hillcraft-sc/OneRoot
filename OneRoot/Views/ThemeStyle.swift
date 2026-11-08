import AppKit
import SwiftUI

extension ThemeColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = ThemeCatalog.nativeDark
}

extension EnvironmentValues {
    /// The theme in effect. Set by `.themed()` at each window's root —
    /// `NSHostingView`/`NSHostingController` boundaries (the sidebar, the
    /// main pane, tab buttons, pane headers) don't inherit the environment,
    /// so each one applies it again.
    var appTheme: Theme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// What the views draw with. Everything falls back to the system color the
/// app used before themes existed, so the native themes look exactly as
/// they always did — only a theme with its own `surfaces` changes anything.
extension Theme {
    // SwiftUI
    var accentColor: Color { surfaces?.accent.color ?? .accentColor }
    var fieldColor: Color { surfaces?.field.color ?? Color(nsColor: .textBackgroundColor) }
    var separatorColor: Color { surfaces?.separator.color ?? Color(nsColor: .separatorColor) }
    var contentBackgroundColor: Color { surfaces?.background.color ?? Color(nsColor: .controlBackgroundColor) }

    // AppKit
    var listBackgroundNSColor: NSColor { surfaces?.background.nsColor ?? .controlBackgroundColor }
    var textNSColor: NSColor { surfaces?.text.nsColor ?? .labelColor }
    var secondaryTextNSColor: NSColor { surfaces?.secondaryText.nsColor ?? .secondaryLabelColor }
    /// `nil` leaves the system's own selection (accent-colored, with the
    /// text flipping to white) in charge.
    var selectionNSColor: NSColor? { surfaces?.selection.nsColor }
    var selectionTextNSColor: NSColor? { surfaces?.selectionText.nsColor }
    var folderNSColor: NSColor { icons.folder.nsColor }
}

extension View {
    /// Applies the current theme to everything below: the environment value
    /// (`appTheme`), the accent (`tint`), and the default text color. Always
    /// the same view structure whatever the theme, so switching themes just
    /// changes values and never rebuilds the view tree (which would reset
    /// state such as selection and scroll position).
    func themed() -> some View {
        modifier(ThemedRoot())
    }

    /// Paints one of the theme's surfaces behind this view — nothing at all
    /// for the native themes, which leave surfaces to macOS.
    func themeBackground(_ role: KeyPath<ThemeSurfaces, ThemeColor>) -> some View {
        modifier(ThemedBackground(role: role))
    }

    /// For a window's outermost content: also colors the window itself (and
    /// with `matchesBars`, its title bar, to line up with the tab strip).
    func themedWindow(matchesBars: Bool = false) -> some View {
        themed().background(WindowThemer(matchesBars: matchesBars))
    }
}

private struct ThemedRoot: ViewModifier {
    private var store = ThemeStore.shared

    func body(content: Content) -> some View {
        let theme = store.current
        content
            .environment(\.appTheme, theme)
            .tint(theme.surfaces?.accent.color)
            .foregroundStyle(theme.surfaces.map { AnyShapeStyle($0.text.color) } ?? AnyShapeStyle(.foreground))
    }
}

private struct ThemedBackground: ViewModifier {
    let role: KeyPath<ThemeSurfaces, ThemeColor>
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.surfaces.map { $0[keyPath: role].color } ?? .clear)
    }
}

/// Colors the `NSWindow` hosting this view: its background (what shows
/// through anywhere the content doesn't paint, the title bar included) and
/// whether the title bar is transparent so that color reaches it.
private struct WindowThemer: NSViewRepresentable {
    let matchesBars: Bool
    private var store = ThemeStore.shared

    func makeNSView(context: Context) -> ThemedWindowView {
        ThemedWindowView()
    }

    func updateNSView(_ view: ThemedWindowView, context: Context) {
        view.theme = store.current
        view.matchesBars = matchesBars
        view.apply()
    }
}

final class ThemedWindowView: NSView {
    var theme = ThemeCatalog.nativeDark
    var matchesBars = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        guard let window else { return }
        if matchesBars {
            // A main window: no title bar of its own (see `OneRootApp`) —
            // the backdrop (`WindowBackdrop`) shows right to the top.
            window.titlebarAppearsTransparent = true
            window.backgroundColor = theme.surfaces?.sidebar.nsColor ?? .windowBackgroundColor
            return
        }
        if let surfaces = theme.surfaces {
            window.backgroundColor = (matchesBars ? surfaces.bar : surfaces.background).nsColor
            window.titlebarAppearsTransparent = true
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}
