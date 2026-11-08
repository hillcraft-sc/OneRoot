import Foundation

/// #70, before a copy or move: when the destination can't store some of
/// the names (`NameCompatibility`), asks once — rename the copies, leave
/// those items out, or cancel. Shared by `FileListViewModel` and
/// `FolderHierarchyViewModel`.
@MainActor
enum NameFixCheck {
    struct Plan {
        var nameFixes: [URL: String] = [:]
        var skipping: Set<URL> = []
    }

    /// The renames/skips to copy with; `nil` means Cancel.
    static func plan(
        for urls: [URL],
        into destination: URL,
        isMove: Bool,
        ask: (NameFixRequest) async -> NameFixAnswer
    ) async -> Plan? {
        let restricts = await Task.detached(priority: .userInitiated) {
            NameCompatibility.restrictsNames(at: destination)
        }.value
        guard restricts else { return Plan() }
        let (fixes, truncated) = await Task.detached(priority: .userInitiated) {
            NameCompatibility.problems(in: urls)
        }.value
        guard !fixes.isEmpty else { return Plan() }
        switch await ask(NameFixRequest(fixes: fixes, destination: destination, isMove: isMove, isTruncated: truncated)) {
        case .rename:
            return Plan(nameFixes: Dictionary(fixes.map { ($0.source, $0.newName) }, uniquingKeysWith: { first, _ in first }))
        case .skip:
            return Plan(skipping: Set(fixes.map(\.source)))
        case .cancel:
            return nil
        }
    }
}
