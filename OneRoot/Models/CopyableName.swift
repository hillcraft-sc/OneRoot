import Foundation

/// What Copy Name puts on the clipboard: each item's name, one per line,
/// optionally without its extension. Folders keep their whole name ("v1.2"
/// is a name, not "v1" plus an extension); packages like "Mail.app" lose
/// theirs like files do.
enum CopyableName {
    static func text(for nodes: [FileNode], includeExtension: Bool) -> String {
        nodes.map { name(of: $0, includeExtension: includeExtension) }.joined(separator: "\n")
    }

    static func name(of node: FileNode, includeExtension: Bool) -> String {
        guard !includeExtension, hasStrippableExtension(node) else { return node.name }
        return (node.name as NSString).deletingPathExtension
    }

    /// Whether "without Extension" would copy anything different.
    static func hasStrippableExtension(_ node: FileNode) -> Bool {
        guard !node.isDirectory || node.isPackage else { return false }
        let stripped = (node.name as NSString).deletingPathExtension
        return !stripped.isEmpty && stripped != node.name
    }
}
