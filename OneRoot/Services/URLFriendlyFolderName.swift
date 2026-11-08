import Foundation

extension URL {
    /// A user-facing name for this folder, unmangling the raw folder names
    /// macOS's File Provider system uses for cloud-storage mounts:
    /// - iCloud Drive's container is literally named `com~apple~CloudDocs`.
    /// - Third-party providers under `~/Library/CloudStorage/` are named
    ///   `<Provider>-<accountID>@<host>` (e.g. "Nextcloud-a8f499f1...@
    ///   nextcloud.example.com") — Finder shows just the provider name for
    ///   these, reading it from the File Provider domain's registered
    ///   display name via a privileged API third-party apps can't call;
    ///   trimming to everything before the first hyphen matches that same
    ///   result for the documented naming convention without needing it.
    ///
    /// Both checks are scoped to their specific parent directory, not
    /// applied to any folder with a hyphen in its name — an ordinary
    /// folder like "Project-Files" must come through unmangled.
    var friendlyFolderName: String {
        let name = lastPathComponent
        let parentName = deletingLastPathComponent().lastPathComponent

        if name == "com~apple~CloudDocs", parentName == "Mobile Documents" {
            return "iCloud Drive"
        }
        if parentName == "CloudStorage", let hyphenIndex = name.firstIndex(of: "-") {
            return String(name[..<hyphenIndex])
        }
        return name
    }
}
