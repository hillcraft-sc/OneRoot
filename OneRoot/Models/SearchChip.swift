import Foundation

/// One condition of a `SearchCriteria`, as a chip: "Kind: Images",
/// "Modified: This Month". Removing it clears just that condition
/// (`SearchChipBuilder.removing`).
struct SearchChip: Identifiable, Equatable {
    enum Field: Hashable {
        case name
        case contents
        case itemType
        case extensions
        case size
        case modifiedWithin
        case modifiedDates
        case kinds
        case tag(String)
        case includeHidden
        case includeCloudStorage
    }

    let field: Field
    let title: String
    let systemImage: String

    var id: Field { field }
}

/// Where chips are shown: the current folder leaves out what only a
/// recursive search has (contents, hidden files, cloud storage).
enum SearchChipContext {
    case folder
    case advancedSearch
}

/// Turns criteria into chips and back. Pure, so the wording is tested.
enum SearchChipBuilder {
    static func chips(for criteria: SearchCriteria, context: SearchChipContext) -> [SearchChip] {
        var chips: [SearchChip] = []
        if !criteria.pattern.isEmpty {
            if criteria.mode == .contents, context == .advancedSearch {
                chips.append(SearchChip(field: .contents, title: "Contains text " + patternText(criteria), systemImage: "text.magnifyingglass"))
            } else if criteria.mode == .nameAndMetadata || context == .folder {
                chips.append(SearchChip(field: .name, title: nameTitle(criteria), systemImage: "textformat"))
            }
        }
        switch criteria.itemType {
        case .filesAndFolders: break
        case .filesOnly: chips.append(SearchChip(field: .itemType, title: "Files only", systemImage: "doc"))
        case .foldersOnly: chips.append(SearchChip(field: .itemType, title: "Folders only", systemImage: "folder"))
        }
        if !criteria.kinds.isEmpty {
            let names = StorageCategory.allCases.filter(criteria.kinds.contains).map(\.title).joined(separator: ", ")
            let symbol = criteria.kinds.count == 1 ? criteria.kinds[0].systemImage : "square.grid.2x2"
            chips.append(SearchChip(field: .kinds, title: "Kind: \(names)", systemImage: symbol))
        }
        if !criteria.extensions.isEmpty {
            chips.append(SearchChip(field: .extensions, title: "Extension: " + criteria.extensions.joined(separator: ", "), systemImage: "doc.badge.ellipsis"))
        }
        if let range = criteria.modifiedWithin {
            chips.append(SearchChip(field: .modifiedWithin, title: "Modified: \(range.title)", systemImage: "calendar"))
        }
        if let dates = datesTitle(after: criteria.modifiedAfter, before: criteria.modifiedBefore) {
            chips.append(SearchChip(field: .modifiedDates, title: dates, systemImage: "calendar"))
        }
        if let size = sizeTitle(min: criteria.minSizeBytes, max: criteria.maxSizeBytes) {
            chips.append(SearchChip(field: .size, title: size, systemImage: "scalemass"))
        }
        for tag in criteria.tags {
            chips.append(SearchChip(field: .tag(tag), title: "Tag: \(tag)", systemImage: "tag"))
        }
        if context == .advancedSearch {
            if criteria.includeHidden {
                chips.append(SearchChip(field: .includeHidden, title: "Including hidden files", systemImage: "eye"))
            }
            if criteria.includeCloudStorage {
                chips.append(SearchChip(field: .includeCloudStorage, title: "Including cloud storage", systemImage: "icloud"))
            }
        }
        return chips
    }

    /// `criteria` without the chip's condition.
    static func removing(_ field: SearchChip.Field, from criteria: SearchCriteria) -> SearchCriteria {
        var criteria = criteria
        switch field {
        case .name, .contents:
            criteria.pattern = ""
            criteria.patternMode = .contains
            criteria.caseSensitive = false
        case .itemType: criteria.itemType = .filesAndFolders
        case .extensions: criteria.extensions = []
        case .size:
            criteria.minSizeBytes = nil
            criteria.maxSizeBytes = nil
        case .modifiedWithin: criteria.modifiedWithin = nil
        case .modifiedDates:
            criteria.modifiedAfter = nil
            criteria.modifiedBefore = nil
        case .kinds: criteria.kinds = []
        case .tag(let tag): criteria.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        case .includeHidden: criteria.includeHidden = false
        case .includeCloudStorage: criteria.includeCloudStorage = false
        }
        return criteria
    }

    // MARK: Wording

    /// "Name: “IMG”", "Name starts with “IMG”", "Name matches /^IMG_\d+/",
    /// with " · Match Case" when it's case-sensitive.
    static func nameTitle(_ criteria: SearchCriteria) -> String {
        let text: String
        switch criteria.patternMode {
        case .contains: text = "Name: " + patternText(criteria)
        case .startsWith: text = "Name starts with " + patternText(criteria)
        case .endsWith: text = "Name ends with " + patternText(criteria)
        case .regex: text = "Name matches " + patternText(criteria)
        }
        return criteria.caseSensitive ? text + " \u{00B7} Match Case" : text
    }

    private static func patternText(_ criteria: SearchCriteria) -> String {
        criteria.patternMode == .regex ? "/\(criteria.pattern)/" : "\u{201C}\(criteria.pattern)\u{201D}"
    }

    /// "Size: over 5 MB", "Size: under 100 KB", "Size: 5 MB – 1 GB".
    static func sizeTitle(min: Int64?, max: Int64?) -> String? {
        switch (min, max) {
        case let (min?, max?): return "Size: \(bytes(min)) \u{2013} \(bytes(max))"
        case let (min?, nil): return "Size: over \(bytes(min))"
        case let (nil, max?): return "Size: under \(bytes(max))"
        case (nil, nil): return nil
        }
    }

    static func datesTitle(after: Date?, before: Date?) -> String? {
        func day(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
        switch (after, before) {
        case let (after?, before?): return "Modified: \(day(after)) \u{2013} \(day(before))"
        case let (after?, nil): return "Modified after \(day(after))"
        case let (nil, before?): return "Modified before \(day(before))"
        case (nil, nil): return nil
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
