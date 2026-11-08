import Foundation

/// Builds an approximate shell equivalent (`find`/`grep`) of a
/// `SearchCriteria` — lets someone see roughly how a search could be run
/// from Terminal instead of (or in addition to) Advanced Search. This is
/// necessarily an approximation, not a guaranteed-identical translation:
/// `SearchService` matches with ICU regular expressions
/// (`NSRegularExpression`), while `find`/`grep`'s own `-E`/extended-regex
/// dialect differs in places (e.g. Unicode property escapes), and `find`'s
/// date/size filters round to whole days/bytes differently than the exact
/// byte/second comparisons `SearchService` does. Good enough to hand
/// someone a starting point, not something to script against byte-for-byte.
struct SearchCommandLineBuilder {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func command(for criteria: SearchCriteria) -> String {
        switch criteria.mode {
        case .nameAndMetadata: return findCommand(for: criteria)
        case .contents: return grepCommand(for: criteria)
        }
    }

    private func findCommand(for criteria: SearchCriteria) -> String {
        var parts = ["find"] + criteria.searchRoots.map { quote($0.path) }

        switch criteria.itemType {
        case .filesOnly: parts.append("-type f")
        case .foldersOnly: parts.append("-type d")
        case .filesAndFolders: break
        }

        if !criteria.includeHidden {
            parts.append("-not -path '*/.*'")
        }

        if !criteria.pattern.isEmpty {
            switch criteria.patternMode {
            case .contains: parts.append("-iname \(quote("*\(criteria.pattern)*"))")
            case .startsWith: parts.append("-iname \(quote("\(criteria.pattern)*"))")
            case .endsWith: parts.append("-iname \(quote("*\(criteria.pattern)"))")
            case .regex: parts.append("-E -iregex \(quote(".*\(criteria.pattern)"))")
            }
        }

        if !criteria.extensions.isEmpty {
            let extensionClauses = criteria.extensions.map { "-iname \(quote("*.\($0)"))" }
            parts.append("\\( \(extensionClauses.joined(separator: " -o ")) \\)")
        }

        if let minSizeBytes = criteria.minSizeBytes {
            parts.append("-size +\(minSizeBytes)c")
        }
        if let maxSizeBytes = criteria.maxSizeBytes {
            parts.append("-size -\(maxSizeBytes)c")
        }
        if let modifiedAfter = criteria.modifiedAfter {
            parts.append("-newermt \(quote(Self.dateFormatter.string(from: modifiedAfter)))")
        }
        if let modifiedBefore = criteria.modifiedBefore {
            parts.append("! -newermt \(quote(Self.dateFormatter.string(from: modifiedBefore)))")
        }

        return parts.joined(separator: " ")
    }

    private func grepCommand(for criteria: SearchCriteria) -> String {
        var flags = ["-r", "-n"]
        if !criteria.caseSensitive {
            flags.append("-i")
        }
        switch criteria.patternMode {
        case .regex: flags.append("-E")
        default: flags.append("-F")
        }
        if !criteria.includeHidden {
            flags.append("--exclude-dir=\(quote(".*"))")
        }
        for fileExtension in criteria.extensions {
            flags.append("--include=\(quote("*.\(fileExtension)"))")
        }

        let parts = ["grep"] + flags + [quote(criteria.pattern)] + criteria.searchRoots.map { quote($0.path) }
        return parts.joined(separator: " ")
    }

    private func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
