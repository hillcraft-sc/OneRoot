import XCTest
@testable import OneRoot

final class ThemeColorTests: XCTestCase {
    func testHexRoundTrip() {
        XCTAssertEqual(ThemeColor(hex: 0xFF7069).hexString, "#FF7069")
        XCTAssertEqual(ThemeColor(hex: 0x000000).hexString, "#000000")
        XCTAssertEqual(ThemeColor(hex: 0x1E1E2E).red, 30.0 / 255, accuracy: 1e-9)
    }

    func testContrastExtremesAndSymmetry() {
        let black = ThemeColor(hex: 0x000000), white = ThemeColor(hex: 0xFFFFFF)
        XCTAssertEqual(black.contrast(with: white), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrast(with: black), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrast(with: white), 1, accuracy: 1e-9)
    }

    func testEnsuringContrastLeavesLegibleColorsAloneAndNudgesFaintOnes() {
        let white = ThemeColor(hex: 0xFFFFFF), black = ThemeColor(hex: 0x000000)
        let legible = ThemeColor(hex: 0x1E66F5)
        XCTAssertEqual(legible.ensuringContrast(3, against: [white]), legible, "already fine: untouched")

        let faint = ThemeColor(hex: 0xFFE9A9)
        let darkened = faint.ensuringContrast(3, against: [white])
        XCTAssertGreaterThanOrEqual(darkened.contrast(with: white), 3)
        XCTAssertLessThan(darkened.relativeLuminance, faint.relativeLuminance, "darkened on a light background")

        let dim = ThemeColor(hex: 0x303030)
        let lightened = dim.ensuringContrast(3, against: [black])
        XCTAssertGreaterThanOrEqual(lightened.contrast(with: black), 3)
        XCTAssertGreaterThan(lightened.relativeLuminance, dim.relativeLuminance, "lightened on a dark background")
    }

    func testBlending() {
        let black = ThemeColor(hex: 0x000000), white = ThemeColor(hex: 0xFFFFFF)
        XCTAssertEqual(black.blended(with: white, amount: 0).hexString, "#000000")
        XCTAssertEqual(black.blended(with: white, amount: 1).hexString, "#FFFFFF")
        XCTAssertEqual(black.blended(with: white, amount: 0.5).hexString, "#808080")
    }
}

final class ThemeCatalogTests: XCTestCase {
    func testIDsAreUniqueAndNeverTheAutomaticChoice() {
        let ids = ThemeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate theme ids: \(ids)")
        XCTAssertFalse(ids.contains(ThemeCatalog.automaticChoiceID))
    }

    func testTheFourRequestedFamiliesAreAllThere() {
        let families = Set(ThemeCatalog.all.map(\.family))
        XCTAssertTrue(families.isSuperset(of: ["macOS", "Catppuccin", "Gruvbox", "Nord", "Tokyo Night"]))
        XCTAssertEqual(ThemeCatalog.all.filter { $0.family == "Catppuccin" }.count, 4)
        XCTAssertEqual(ThemeCatalog.all.filter { $0.family == "Tokyo Night" }.count, 3)
    }

    func testNativeThemesLeaveSurfacesToMacOS() {
        XCTAssertNil(ThemeCatalog.nativeLight.surfaces)
        XCTAssertNil(ThemeCatalog.nativeDark.surfaces)
        XCTAssertFalse(ThemeCatalog.nativeDark.icons.recolorsSidebarIcons, "dark keeps the original artwork")
        XCTAssertTrue(ThemeCatalog.nativeLight.icons.recolorsSidebarIcons)
    }

    func testDarknessMatchesTheBackground() {
        for theme in ThemeCatalog.all {
            guard let background = theme.surfaces?.background else { continue }
            XCTAssertEqual(theme.isDark, background.relativeLuminance < 0.2, "\(theme.displayName): isDark disagrees with its background \(background.hexString)")
        }
    }

    /// Every theme must be readable. Collects all failures into one message so a bad
    /// palette shows everything wrong with it at once.
    func testEveryThemeIsLegible() {
        var failures: [String] = []
        func check(_ theme: Theme, _ label: String, _ a: ThemeColor, _ b: ThemeColor, atLeast minimum: Double) {
            let ratio = a.contrast(with: b)
            if ratio < minimum {
                failures.append("\(theme.displayName): \(label) \(a.hexString) on \(b.hexString) is \(String(format: "%.2f", ratio)):1, needs \(minimum)")
            }
        }

        for theme in ThemeCatalog.all {
            let icons = theme.icons
            let iconRoles: [(String, ThemeColor)] = [
                ("folder", icons.folder), ("drive", icons.drive), ("volume", icons.volume), ("network", icons.network),
                ("cloud", icons.cloud), ("pinned", icons.pinned), ("trash", icons.trash), ("applications", icons.applications),
            ]
            if let s = theme.surfaces {
                for (name, surface) in [("background", s.background), ("sidebar", s.sidebar), ("bar", s.bar), ("field", s.field)] {
                    check(theme, "text/\(name)", s.text, surface, atLeast: 4.5)
                    check(theme, "secondary text/\(name)", s.secondaryText, surface, atLeast: 3.0)
                }
                check(theme, "selection text/selection", s.selectionText, s.selection, atLeast: 4.5)
                check(theme, "accent/background", s.accent, s.background, atLeast: 3.0)
                check(theme, "accent/sidebar", s.accent, s.sidebar, atLeast: 3.0)
                // Icons sit on the sidebar and on the list background.
                for (role, color) in iconRoles {
                    check(theme, "\(role) icon/sidebar", color, s.sidebar, atLeast: 3.0)
                    check(theme, "\(role) icon/background", color, s.background, atLeast: 3.0)
                }
                check(theme, "toolbar primary/bar", icons.toolbarPrimary, s.bar, atLeast: 3.0)
                check(theme, "toolbar secondary/bar", icons.toolbarSecondary, s.bar, atLeast: 3.0)
                XCTAssertNotEqual(s.separator, s.background, "\(theme.displayName): separator vanishes into the background")
                XCTAssertNotEqual(s.selection, s.background, "\(theme.displayName): selection vanishes into the background")
            } else {
                // macOS draws these surfaces, so test against typical ones: white, and a dark gray.
                let surface = theme.isDark ? ThemeColor(hex: 0x2B2B2B) : ThemeColor(hex: 0xFFFFFF)
                for (role, color) in iconRoles {
                    check(theme, "\(role) icon", color, surface, atLeast: 3.0)
                }
                check(theme, "toolbar primary", icons.toolbarPrimary, surface, atLeast: 3.0)
                check(theme, "toolbar secondary", icons.toolbarSecondary, surface, atLeast: 3.0)
            }
        }
        XCTAssertEqual(failures, [], "\n" + failures.joined(separator: "\n"))
    }
}

@MainActor
final class ThemeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var systemDark = true
    private var appliedAppearances: [Bool?] = []

    override func setUp() async throws {
        suiteName = "ThemeStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        systemDark = true
        appliedAppearances = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> ThemeStore {
        ThemeStore(
            preferences: ThemePreferenceService(defaults: defaults),
            systemIsDark: { [unowned self] in self.systemDark },
            applyAppearance: { [unowned self] in self.appliedAppearances.append($0) },
            observesSystemAppearance: false
        )
    }

    func testDefaultsToTheOneRootLookFollowingTheSystem() {
        XCTAssertEqual(makeStore().choiceID, ThemeCatalog.automaticChoiceID)
        XCTAssertEqual(makeStore().current, ThemeCatalog.oneRootDark)
        systemDark = false
        XCTAssertEqual(makeStore().current, ThemeCatalog.oneRootLight)
    }

    func testAutomaticFlipsWhenTheSystemAppearanceDoes() {
        let store = makeStore()
        XCTAssertEqual(store.current, ThemeCatalog.oneRootDark)

        systemDark = false
        store.systemAppearanceChanged()

        XCTAssertEqual(store.current, ThemeCatalog.oneRootLight)
    }

    func testMacOSAutomaticFollowsTheSystemWithTheNativeThemes() {
        let store = makeStore()

        store.choose(ThemeCatalog.nativeAutomaticChoiceID)
        XCTAssertEqual(store.current, ThemeCatalog.nativeDark)
        XCTAssertEqual(appliedAppearances.last, .some(nil))

        systemDark = false
        store.systemAppearanceChanged()
        XCTAssertEqual(store.current, ThemeCatalog.nativeLight)
        XCTAssertEqual(makeStore().choiceID, ThemeCatalog.nativeAutomaticChoiceID, "remembered")
    }

    func testOnlyTheOneRootThemesUseTheMaterialBackdrop() {
        XCTAssertEqual(ThemeCatalog.all.filter(\.usesMaterialBackdrop).map(\.id), ["oneroot-light", "oneroot-dark"])
    }

    func testAChosenThemeIgnoresSystemChangesAndPinsTheAppearance() throws {
        let store = makeStore()
        let latte = try XCTUnwrap(ThemeCatalog.theme(withID: "catppuccin-latte"))

        store.choose(latte.id)
        systemDark = true
        store.systemAppearanceChanged()

        XCTAssertEqual(store.current, latte)
        XCTAssertEqual(appliedAppearances.last, .some(false), "light theme pins the light appearance")
    }

    func testReturningToAutomaticUnpinsTheAppearance() {
        let store = makeStore()
        store.choose("nord")
        XCTAssertEqual(appliedAppearances.last, .some(true))

        store.choose(ThemeCatalog.automaticChoiceID)

        XCTAssertEqual(appliedAppearances.last, .some(nil), "nil = follow the system again")
    }

    /// Setting the app's appearance back to "follow macOS" makes macOS report
    /// an appearance change, which reaches `systemAppearanceChanged` — from
    /// *inside* the store's own `applyAppearance` call. That must not loop.
    func testChoosingAutomaticSurvivesTheAppearanceChangeItTriggers() throws {
        var reentries = 0
        var store: ThemeStore?
        store = ThemeStore(
            preferences: ThemePreferenceService(defaults: defaults),
            systemIsDark: { [unowned self] in self.systemDark },
            applyAppearance: { [unowned self] appearance in
                self.appliedAppearances.append(appearance)
                guard appearance == nil, reentries < 50 else { return }
                reentries += 1
                store?.systemAppearanceChanged() // what macOS's notification does
            },
            observesSystemAppearance: false
        )
        let live = try XCTUnwrap(store)
        live.choose("nord")
        reentries = 0
        appliedAppearances = []

        live.choose(ThemeCatalog.automaticChoiceID)

        XCTAssertLessThan(reentries, 3, "re-resolved \(reentries) times: a feedback loop")
        XCTAssertEqual(live.current, ThemeCatalog.oneRootDark)
    }

    func testAnEarlierChoiceSwitchesToTheOneRootLookOnce() {
        defaults.set("native-light", forKey: "com.oneroot.theme")

        XCTAssertEqual(makeStore().choiceID, ThemeCatalog.automaticChoiceID)

        makeStore().choose("native-light")
        XCTAssertEqual(makeStore().choiceID, "native-light", "a choice made afterwards sticks")
    }

    func testChoiceIsRemembered() {
        makeStore().choose("gruvbox-dark")

        XCTAssertEqual(makeStore().choiceID, "gruvbox-dark")
        XCTAssertEqual(makeStore().current.id, "gruvbox-dark")
    }

    func testUnknownThemesAreIgnoredAndStaleStoredOnesFallBackToAutomatic() {
        let store = makeStore()
        store.choose("no-such-theme")
        XCTAssertEqual(store.choiceID, ThemeCatalog.automaticChoiceID)

        defaults.set("removed-in-a-later-version", forKey: "com.oneroot.theme")
        XCTAssertEqual(makeStore().choiceID, ThemeCatalog.automaticChoiceID)
    }
}
