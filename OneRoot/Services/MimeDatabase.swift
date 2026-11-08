import Foundation

/// File types the way the Linux desktops know them: the freedesktop.org
/// shared MIME database (/usr/share/mime) — which type a file name means
/// (`globs2`), and that type's name for people ("PNG image") from its own
/// file, in the user's language where there is one. Read lazily and kept;
/// injectable for tests.
final class MimeDatabase: @unchecked Sendable {
    static let shared = MimeDatabase(root: URL(fileURLWithPath: "/usr/share/mime", isDirectory: true))

    private let root: URL
    private let lock = NSLock()
    private var globs: (extensions: [String: String], names: [String: String])?
    private var comments: [String: String] = [:]

    init(root: URL) {
        self.root = root
    }

    /// "image/png" for "Photo.PNG"; `nil` when nothing matches.
    func type(forFileName name: String) -> String? {
        let (extensions, names) = loadedGlobs()
        let lower = name.lowercased()
        if let exact = names[lower] { return exact }
        // Longest extension first: "archive.tar.gz" is a tarball, not just gzip.
        var rest = Substring(lower)
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            if let type = extensions[String(rest)] { return type }
        }
        return nil
    }

    /// "PNG image" for "image/png" — in the user's language if the database
    /// has it.
    func description(ofType type: String) -> String? {
        lock.lock()
        if let cached = comments[type] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()
        let found = readComment(type) ?? ""
        lock.lock()
        comments[type] = found
        lock.unlock()
        return found.isEmpty ? nil : found
    }

    /// The kind to show for a file: its type's description, else a plain one.
    func kind(forFileName name: String, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        guard let type = type(forFileName: name) else {
            let ext = (name as NSString).pathExtension
            return ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
        }
        return description(ofType: type) ?? type
    }

    // MARK: Reading

    private func loadedGlobs() -> (extensions: [String: String], names: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        if let globs { return globs }
        var extensions: [String: String] = [:]
        var names: [String: String] = [:]
        var weights: [String: Int] = [:]
        let text = (try? String(contentsOf: root.appendingPathComponent("globs2"), encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            // weight:type:glob[:flags]
            let fields = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count >= 3, let weight = Int(fields[0]) else { continue }
            let type = String(fields[1])
            let glob = String(fields[2]).lowercased()
            if glob.hasPrefix("*."), !glob.dropFirst(2).contains(where: { "*?[".contains($0) }) {
                let ext = String(glob.dropFirst(2))
                if weight > weights["." + ext, default: -1] {
                    weights["." + ext] = weight
                    extensions[ext] = type
                }
            } else if !glob.contains(where: { "*?[".contains($0) }) {
                names[glob] = names[glob] ?? type
            }
        }
        globs = (extensions, names)
        return (extensions, names)
    }

    private func readComment(_ type: String) -> String? {
        guard let text = try? String(contentsOf: root.appendingPathComponent(type + ".xml"), encoding: .utf8) else { return nil }
        let languages = Self.preferredLanguages()
        var plain: String?
        var localized: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<comment"), let open = trimmed.firstIndex(of: ">"),
                  let close = trimmed.range(of: "</comment>") else { continue }
            let value = Self.unescape(String(trimmed[trimmed.index(after: open)..<close.lowerBound]))
            if let langRange = trimmed.range(of: "xml:lang=\"") {
                let lang = trimmed[langRange.upperBound...].prefix { $0 != "\"" }
                localized[String(lang)] = value
            } else if plain == nil {
                plain = value
            }
        }
        for language in languages {
            if let value = localized[language] { return value }
        }
        return plain
    }

    /// "pt_BR" then "pt", from the locale.
    private static func preferredLanguages() -> [String] {
        let identifier = Locale.current.identifier.split(separator: ".").first.map(String.init) ?? ""
        guard !identifier.isEmpty, !identifier.hasPrefix("en") else { return [] }
        let base = identifier.split(separator: "_").first.map(String.init) ?? identifier
        return identifier == base ? [base] : [identifier, base]
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
