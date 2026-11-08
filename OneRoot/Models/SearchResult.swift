import Foundation

/// One line matched during a content-mode (grep-style) search.
struct ContentMatch {
    let lineNumber: Int
    let snippet: String
}

/// One row in the Advanced Search results table — a `FileNode` that matched
/// `SearchCriteria`, plus the matched line when the search ran in
/// `.contents` mode. A single file can produce several `SearchResult`s in
/// content mode, one per matching line.
struct SearchResult: Identifiable {
    let id = UUID()
    let node: FileNode
    let contentMatch: ContentMatch?
    /// A cloud file that isn't on this Mac yet — only a placeholder. Found
    /// by name like any other, but never opened by a content search, which
    /// would make macOS download it.
    var isCloudOnly = false
}
