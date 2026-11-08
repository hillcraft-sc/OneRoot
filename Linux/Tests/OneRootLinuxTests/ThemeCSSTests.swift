import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class ThemeCSSTests: XCTestCase {
    func testSystemThemesAddNoCSS() {
        XCTAssertEqual(ThemeCSS.css(for: ThemeCatalog.nativeLight), "")
        XCTAssertEqual(ThemeCSS.css(for: ThemeCatalog.nativeDark), "")
    }

    func testOneRootThemeDefinesLibadwaitaColorsFromItsSurfaces() throws {
        let theme = ThemeCatalog.oneRootLight
        let surfaces = try XCTUnwrap(theme.surfaces)
        let css = ThemeCSS.css(for: theme)
        XCTAssertTrue(css.contains("@define-color view_bg_color \(surfaces.background.hexString);"))
        XCTAssertTrue(css.contains("@define-color sidebar_bg_color \(surfaces.sidebar.hexString);"))
        XCTAssertTrue(css.contains("@define-color headerbar_bg_color \(surfaces.bar.hexString);"))
        XCTAssertTrue(css.contains("@define-color accent_bg_color \(surfaces.accent.hexString);"))
        XCTAssertTrue(css.contains("row:selected"))
    }

    func testEveryThemeWithSurfacesColorsTheSidebarIcons() throws {
        for theme in ThemeCatalog.all where theme.surfaces != nil {
            let css = ThemeCSS.css(for: theme)
            for name in ["folder", "drive", "volume", "network", "cloud", "pinned", "trash", "applications"] {
                XCTAssertTrue(css.contains(".oneroot-icon-\(name) { color: "), "\(theme.id) lacks \(name)")
            }
        }
    }

    func testAccentTextIsWhiteOnDarkAccentsAndBlackOnLightOnes() {
        XCTAssertEqual(ThemeCSS.readableOn(ThemeColor(hex: 0x1B3A8C)), ThemeColor(hex: 0xFFFFFF))
        XCTAssertEqual(ThemeCSS.readableOn(ThemeColor(hex: 0xF9E2AF)), ThemeColor(hex: 0x000000))
    }

    func testEveryDestinationKindHasAnIconClassTheCSSDefines() {
        let css = ThemeCSS.css(for: ThemeCatalog.oneRootDark)
        let kinds: [DestinationKind] = [.home, .applications, .bootVolume, .volume, .networkVolume, .cloud, .pinned, .folder, .trash, .recents, .shared]
        for kind in kinds {
            XCTAssertTrue(css.contains("." + ThemeCSS.iconClass(for: kind) + " {"), "\(kind)")
        }
    }
}
