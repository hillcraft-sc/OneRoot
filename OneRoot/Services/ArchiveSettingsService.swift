import Foundation

/// Where `ArchiveService.compress` should write its output.
enum ArchiveOutputLocation: String {
    /// Next to whatever's being compressed — the default, matching Finder.
    case sameAsSource
    /// Always the same folder, configured in Settings > Archives.
    case fixedDirectory
    /// Prompt for a destination on every compress.
    case askEachTime
}

/// Persists Settings > Archives: which engine/format `ArchiveService` uses,
/// and where it writes compressed output. Same `UserDefaults`-backed shape
/// as `TerminalPreferenceService`.
struct ArchiveSettingsService {
    private static let toolKey = "com.oneroot.archiveTool"
    private static let formatKey = "com.oneroot.archiveFormat"
    private static let outputLocationKey = "com.oneroot.archiveOutputLocation"
    private static let fixedDirectoryKey = "com.oneroot.archiveFixedDirectory"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func tool() -> ArchiveTool {
        defaults.string(forKey: Self.toolKey).flatMap(ArchiveTool.init(rawValue:)) ?? Platform.defaultArchiveTool
    }

    func setTool(_ tool: ArchiveTool) {
        defaults.set(tool.rawValue, forKey: Self.toolKey)
    }

    /// Only meaningful when `tool()` isn't `.appleDitto` — ditto only ever
    /// produces zip.
    func format() -> ArchiveFormat {
        defaults.string(forKey: Self.formatKey).flatMap(ArchiveFormat.init(rawValue:)) ?? .zip
    }

    func setFormat(_ format: ArchiveFormat) {
        defaults.set(format.rawValue, forKey: Self.formatKey)
    }

    func outputLocation() -> ArchiveOutputLocation {
        defaults.string(forKey: Self.outputLocationKey).flatMap(ArchiveOutputLocation.init(rawValue:)) ?? .sameAsSource
    }

    func setOutputLocation(_ location: ArchiveOutputLocation) {
        defaults.set(location.rawValue, forKey: Self.outputLocationKey)
    }

    /// Only meaningful when `outputLocation()` is `.fixedDirectory`.
    func fixedDirectory() -> URL? {
        defaults.url(forKey: Self.fixedDirectoryKey)
    }

    func setFixedDirectory(_ url: URL?) {
        guard let url else {
            defaults.removeObject(forKey: Self.fixedDirectoryKey)
            return
        }
        defaults.set(url, forKey: Self.fixedDirectoryKey)
    }
}
