import XCTest
@testable import OneRootLinux

final class TerminalPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "TerminalPreferenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func installed(_ names: [String]) -> (String) -> Bool {
        { path in names.contains(path) }
    }

    func testPicksTheFirstInstalledKnownTerminal() {
        let preference = TerminalPreference(defaults: defaults)
        let result = preference.resolve(environment: ["PATH": "/usr/bin"], isExecutable: installed(["/usr/bin/kitty", "/usr/bin/xterm"]))
        XCTAssertEqual(result, .found(executable: "/usr/bin/kitty", arguments: []))
    }

    func testTheTerminalEnvironmentVariableComesFirst() {
        let preference = TerminalPreference(defaults: defaults)
        let result = preference.resolve(
            environment: ["PATH": "/usr/bin", "TERMINAL": "foot --server"],
            isExecutable: installed(["/usr/bin/foot", "/usr/bin/kitty"])
        )
        XCTAssertEqual(result, .found(executable: "/usr/bin/foot", arguments: ["--server"]))
    }

    func testTheSettingsCommandBeatsTheEnvironmentAndKeepsItsArguments() {
        let preference = TerminalPreference(defaults: defaults)
        preference.command = "  kitty --single-instance  "
        XCTAssertEqual(preference.command, "kitty --single-instance")
        let result = preference.resolve(
            environment: ["PATH": "/usr/bin", "TERMINAL": "foot"],
            isExecutable: installed(["/usr/bin/foot", "/usr/bin/kitty"])
        )
        XCTAssertEqual(result, .found(executable: "/usr/bin/kitty", arguments: ["--single-instance"]))
    }

    func testAConfiguredTerminalThatIsMissingIsReportedNotReplaced() {
        let preference = TerminalPreference(defaults: defaults)
        preference.command = "ghostty"
        let result = preference.resolve(environment: ["PATH": "/usr/bin"], isExecutable: installed(["/usr/bin/xterm"]))
        XCTAssertEqual(result, .missingConfigured("ghostty"))
    }

    func testAbsolutePathsAreUsedAsGiven() {
        let preference = TerminalPreference(defaults: defaults)
        preference.command = "/opt/term/bin/myterm -x"
        let result = preference.resolve(environment: [:], isExecutable: installed(["/opt/term/bin/myterm"]))
        XCTAssertEqual(result, .found(executable: "/opt/term/bin/myterm", arguments: ["-x"]))
    }

    func testNothingInstalledAndNothingSet() {
        XCTAssertEqual(TerminalPreference(defaults: defaults).resolve(environment: ["PATH": "/usr/bin"], isExecutable: { _ in false }), .noneFound)
    }

    func testClearingTheCommandRestoresTheAutomaticChoice() {
        let preference = TerminalPreference(defaults: defaults)
        preference.command = "kitty"
        preference.command = "   "
        XCTAssertNil(preference.command)
        XCTAssertNil(defaults.string(forKey: TerminalPreference.key))
    }
}
