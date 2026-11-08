import Foundation

/// Compiles `SearchCriteria`'s pattern/mode once up front rather than
/// re-parsing a regex (or re-lowercasing a search string) for every file and
/// every line — matters once this is running against a whole volume.
struct CompiledPattern {
    let mode: SearchPatternMode
    let caseSensitive: Bool
    let text: String
    let regex: NSRegularExpression?

    init(pattern: String, mode: SearchPatternMode, caseSensitive: Bool) throws {
        self.mode = mode
        self.caseSensitive = caseSensitive
        self.text = caseSensitive ? pattern : pattern.lowercased()
        if mode == .regex {
            do {
                regex = try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
            } catch {
                throw SearchError.invalidRegex(pattern)
            }
        } else {
            regex = nil
        }
    }

    func matches(_ value: String) -> Bool {
        switch mode {
        case .regex:
            let range = NSRange(value.startIndex..., in: value)
            return regex?.firstMatch(in: value, range: range) != nil
        case .contains:
            return caseSensitive ? value.contains(text) : value.lowercased().contains(text)
        case .startsWith:
            return caseSensitive ? value.hasPrefix(text) : value.lowercased().hasPrefix(text)
        case .endsWith:
            return caseSensitive ? value.hasSuffix(text) : value.lowercased().hasSuffix(text)
        }
    }
}

/// Whether a file or folder meets `SearchCriteria` — shared by the
/// current folder's filter (`FileListViewModel`) and `SearchService`, so a
/// filter means the same in both. Compiles the pattern once; cheap to run
/// on every item.
struct SearchCriteriaMatcher {
    let criteria: SearchCriteria
    private let pattern: CompiledPattern
    private let modifiedFrom: Date?
    private let tags: [String]

    /// Throws `SearchError.invalidRegex` for a bad regex.
    init(_ criteria: SearchCriteria, now: Date = Date(), calendar: Calendar = .current) throws {
        self.criteria = criteria
        pattern = try CompiledPattern(pattern: criteria.pattern, mode: criteria.patternMode, caseSensitive: criteria.caseSensitive)
        modifiedFrom = criteria.modifiedWithin?.start(now: now, calendar: calendar)
        tags = criteria.tags.map { $0.lowercased() }
    }

    /// Everything a name/metadata search checks: the name, files/folders,
    /// and the filters.
    func matches(_ node: FileNode) -> Bool {
        matchesItemType(node) && matchesName(node.name) && passesFilters(node)
    }

    /// The name pattern (an empty one matches everything).
    func matchesName(_ name: String) -> Bool {
        criteria.pattern.isEmpty || pattern.matches(name)
    }

    /// A content search's line pattern.
    func matchesLine(_ line: String) -> Bool {
        pattern.matches(line)
    }

    func matchesItemType(_ node: FileNode) -> Bool {
        switch criteria.itemType {
        case .filesAndFolders: return true
        case .filesOnly: return !node.isDirectory
        case .foldersOnly: return node.isDirectory
        }
    }

    /// Extension, size, dates, kind, and tags — not the name.
    func passesFilters(_ node: FileNode) -> Bool {
        if !criteria.extensions.isEmpty, !criteria.extensions.contains(node.fileExtension.lowercased()) {
            return false
        }
        if let minSizeBytes = criteria.minSizeBytes, (node.size ?? 0) < minSizeBytes {
            return false
        }
        if let maxSizeBytes = criteria.maxSizeBytes, (node.size ?? 0) > maxSizeBytes {
            return false
        }
        let modified = node.modificationDate ?? .distantPast
        if let modifiedAfter = criteria.modifiedAfter, modified < modifiedAfter {
            return false
        }
        if let modifiedBefore = criteria.modifiedBefore, modified > modifiedBefore {
            return false
        }
        if let modifiedFrom, modified < modifiedFrom {
            return false
        }
        if !criteria.kinds.isEmpty {
            guard let kind = Self.kind(of: node), criteria.kinds.contains(kind) else { return false }
        }
        if !tags.isEmpty {
            let nodeTags = Set(node.tags.map { $0.lowercased() })
            if !tags.allSatisfy(nodeTags.contains) { return false }
        }
        return true
    }

    /// A file's kind from its extension, the way Visualize groups them.
    /// Plain folders have no kind (a Kind filter leaves them out); an app
    /// or other package has its own.
    static func kind(of node: FileNode) -> StorageCategory? {
        if node.isDirectory, !node.isPackage { return nil }
        return Platform.storageCategory(forExtension: node.fileExtension)
    }
}
