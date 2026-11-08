import Foundation

/// How this copy of OneRoot was installed. Package managers (.deb, .rpm, AUR,
/// Flatpak) update the app themselves, so only a copy installed by the
/// tarball's `install.sh` checks GitHub for a newer release: `install.sh`
/// writes `share/oneroot/install-method` ("tarball") beside the binary's
/// prefix, and the packages don't ship it. A copy run from a build folder has
/// no marker either, so developers aren't nagged.
enum InstallMethod: Equatable {
    case tarball
    case other

    static let markerName = "install-method"

    /// `ONEROOT_INSTALL_METHOD=tarball` forces the answer (the UI harness uses it).
    static let current: InstallMethod = detect(
        executable: URL(fileURLWithPath: (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]),
        environment: ProcessInfo.processInfo.environment
    )

    static func detect(executable: URL, environment: [String: String]) -> InstallMethod {
        if let forced = environment["ONEROOT_INSTALL_METHOD"] { return forced == "tarball" ? .tarball : .other }
        let prefix = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let marker = prefix.appendingPathComponent("share/oneroot/\(markerName)")
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return .other }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "tarball" ? .tarball : .other
    }

    var checksForUpdates: Bool { self == .tarball }
}
