import Foundation

/// Detects whether the app currently holds the user-granted Full Disk Access
/// TCC permission. There's no public API for this, so — like most apps that
/// need to know — we probe a file that's only readable with FDA granted:
/// `TCC.db` itself, which macOS protects even from processes that otherwise
/// have ordinary POSIX read permission on `/Library/Application Support`.
enum FullDiskAccessChecker {
    static let defaultProbePath = "/Library/Application Support/com.apple.TCC/TCC.db"

    static func hasAccess(probingPath path: String = defaultProbePath) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }
}
