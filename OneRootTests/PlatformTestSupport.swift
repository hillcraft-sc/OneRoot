import XCTest
import Foundation

/// On Linux, sends Trash to a throwaway folder for the rest of the run
/// instead of the machine's real one (the freedesktop Trash lives under
/// $XDG_DATA_HOME). On macOS it does nothing.
func isolateTrashOnLinux() {
    #if os(Linux)
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("OneRootTests-data-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    setenv("XDG_DATA_HOME", data.path, 1)
    #endif
}

/// For shared tests of behavior Linux doesn't have yet: skipped there
/// (with the reason in the test log) until the Linux implementation lands
/// in phase 4 (#81); run as usual on macOS.
func skipOnLinuxUntilPhase4(_ what: String) throws {
    #if os(Linux)
    throw XCTSkip("\(what) on Linux arrives in phase 4 (#81)")
    #endif
}

extension UserDefaults {
    /// A throwaway defaults domain: the test host shares the real app's
    /// `com.oneroot.OneRoot` defaults, so `.standard` would read whatever
    /// the developer has set (like Show progress in the window).
    static func isolatedForTests() -> UserDefaults {
        UserDefaults(suiteName: "OneRootTests-\(UUID().uuidString)") ?? .standard
    }
}
