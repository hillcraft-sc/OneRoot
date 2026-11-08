import Foundation

/// Translates the parts of a `SearchCriteria` Spotlight can express into a
/// Spotlight query string, for `SearchService`'s indexed path. The query is
/// only a *candidate* filter: every result is still checked against the
/// full criteria on disk, so it's fine for it to match more than the
/// criteria would — never less.
enum SpotlightQueryBuilder {
    /// `nil` when Spotlight can't narrow the search usefully: a regex
    /// (Spotlight has no regex support), or nothing to search by at all
    /// (no name, extension, or minimum size), which would just list every
    /// indexed item under the root.
    static func query(for criteria: SearchCriteria) -> String? {
        guard criteria.patternMode != .regex || criteria.pattern.isEmpty else { return nil }

        var clauses: [String] = []
        if !criteria.pattern.isEmpty {
            let text = escape(criteria.pattern)
            let wildcarded: String
            switch criteria.patternMode {
            case .contains, .regex: wildcarded = "*\(text)*"
            case .startsWith: wildcarded = "\(text)*"
            case .endsWith: wildcarded = "*\(text)"
            }
            clauses.append(nameClause(wildcarded, caseSensitive: criteria.caseSensitive))
        }
        if !criteria.extensions.isEmpty {
            let alternatives = criteria.extensions.map { nameClause("*.\(escape($0))", caseSensitive: false) }
            clauses.append(alternatives.count == 1 ? alternatives[0] : "(\(alternatives.joined(separator: " || ")))")
        }
        // Folders have no size of their own, so the full scan treats them
        // as 0 bytes — a minimum excludes them either way, which makes this
        // safe to push into the query. (A maximum isn't: Spotlight would
        // drop folders the full scan keeps.)
        if let minSizeBytes = criteria.minSizeBytes, minSizeBytes > 0 {
            clauses.append("kMDItemFSSize >= \(minSizeBytes)")
        }

        return clauses.isEmpty ? nil : clauses.joined(separator: " && ")
    }

    private static func nameClause(_ value: String, caseSensitive: Bool) -> String {
        "kMDItemFSName == \"\(value)\"\(caseSensitive ? "" : "c")"
    }

    /// Backslash-escapes the characters that are special inside a quoted
    /// Spotlight value — the quote itself, the `*` wildcard, and the
    /// backslash.
    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "\"" || character == "*" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
