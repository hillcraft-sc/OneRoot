import Foundation

/// The engine `ArchiveService` shells out to for compress/extract. `.appleDitto`
/// is always available (it's a system binary); `.p7zip` is only offered once
/// detected on disk. See `ArchiveService` for the actual commands.
///
/// Keka was considered and dropped: its `--cli` mode crashes with an
/// uncaught `NSInvalidArgumentException` ("task not launched") trying to
/// spawn its own bundled `7z` from inside its sandbox, even once its own
/// File Access setting has been granted — a sandboxing limitation in Keka
/// itself, not something fixable from this side of the process boundary.
enum ArchiveTool: String, CaseIterable {
    case appleDitto
    case p7zip
    /// libarchive's `bsdtar` — on every Linux desktop (Linux's default).
    case libarchive

    var displayName: String {
        switch self {
        case .appleDitto: return "Apple (Archive Utility)"
        case .p7zip: return "p7zip"
        case .libarchive: return "libarchive (bsdtar)"
        }
    }

    /// Where each tool's CLI entry point lives. p7zip ships under either
    /// Homebrew prefix depending on Mac architecture.
    private static let ditto = "/usr/bin/ditto"
    private static let p7zipCandidates = ["/opt/homebrew/bin/7z", "/usr/local/bin/7z", "/usr/bin/7z", "/usr/bin/7zz", "/usr/bin/7za"]
    private static let bsdtarCandidates = ["/usr/bin/bsdtar", "/bin/bsdtar", "/opt/homebrew/bin/bsdtar", "/usr/local/bin/bsdtar"]

    var isInstalled: Bool {
        switch self {
        case .appleDitto:
            return FileManager.default.isExecutableFile(atPath: Self.ditto)
        case .p7zip:
            return Self.p7zipCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
        case .libarchive:
            return Self.bsdtarCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
        }
    }

    /// Resolves to whichever `p7zipCandidates` entry actually exists for
    /// `.p7zip`. Returns `nil` if the tool isn't installed.
    var executablePath: String? {
        switch self {
        case .appleDitto:
            return Self.ditto
        case .p7zip:
            return Self.p7zipCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        case .libarchive:
            return Self.bsdtarCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
    }

    /// File extensions (lowercase, no leading dot) this tool can extract.
    /// `ditto` only ever produces/reads the zip it makes itself. p7zip
    /// wraps `7z`, which handles the zip/7z/tar/compressed-tar family, but
    /// not `.rar` — its Homebrew build has RAR support stripped (licensing).
    var extractableExtensions: Set<String> {
        switch self {
        case .appleDitto:
            return ["zip"]
        case .p7zip:
            return ["zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]
        case .libarchive:
            return ["zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "tzst", "rar", "iso", "cpio"]
        }
    }
}

/// The container format `ArchiveService.compress` produces. `ditto` only
/// ever makes zip files; p7zip can also target `.7z`.
enum ArchiveFormat: String, CaseIterable {
    case zip
    case sevenZip

    var displayName: String {
        switch self {
        case .zip: return "Zip"
        case .sevenZip: return "7z"
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        }
    }
}
