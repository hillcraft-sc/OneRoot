import Foundation

/// The desktop's own folders on Linux — Desktop, Documents, Downloads,
/// Music, Pictures, Videos — as `xdg-user-dirs` keeps them in
/// ~/.config/user-dirs.dirs (localized names included, e.g. "Bilder").
/// Pure parsing, so it builds and tests on both platforms.
enum XDGUserDirectories {
    /// The sidebar's order (Nautilus' and Dolphin's).
    static let sidebarKeys = ["DESKTOP", "DOCUMENTS", "DOWNLOAD", "MUSIC", "PICTURES", "VIDEOS"]

    /// The folders in `sidebarKeys` order that the file names, skipping any
    /// set to the home folder itself (how xdg-user-dirs turns one off).
    static func folders(in contents: String, home: URL) -> [URL] {
        let byKey = parse(contents, home: home)
        let homePath = home.standardizedFileURL.path
        return sidebarKeys.compactMap { byKey[$0] }.filter { $0.standardizedFileURL.path != homePath }
    }

    /// `XDG_DOWNLOAD_DIR="$HOME/Downloads"` → ["DOWNLOAD": ~/Downloads].
    static func parse(_ contents: String, home: URL) -> [String: URL] {
        var result: [String: URL] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("XDG_"), !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=") else { continue }
            let name = line[line.index(line.startIndex, offsetBy: 4)..<equals]
            guard name.hasSuffix("_DIR") else { continue }
            let key = String(name.dropLast(4))
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            value = value.replacingOccurrences(of: "\\\"", with: "\"")
            let path: String
            if value.hasPrefix("$HOME") {
                path = home.path + value.dropFirst(5)
            } else if value.hasPrefix("/") {
                path = value
            } else {
                continue // the spec allows only these two forms
            }
            result[key] = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return result
    }

    /// The current user's folders that exist (reads the disk).
    static func current(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        guard let contents = try? String(contentsOf: configHome.appendingPathComponent("user-dirs.dirs"), encoding: .utf8) else {
            return []
        }
        return folders(in: contents, home: home).filter {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
