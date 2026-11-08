import Foundation

/// A Help topic's stable identity — what the UI's help buttons and the Help
/// menu ask the Help window to show (`HelpNavigator`), so a topic can be
/// retitled or moved without breaking those links.
enum HelpTopicID: String, CaseIterable, Hashable {
    case gettingStarted
    case comingFromWindows
    case destinations
    case workspaces
    case tabs
    case dualPane
    case navigating
    case fileList
    case contextBar
    case inspector
    case fileOperations
    case fileOperationsCenter
    case compress
    case quickActions
    case advancedSearch
    case visualize
    case networkShares
    case copyViaSSH
    case terminal
    case themes
    case settings
    case shortcuts
}

/// The groups the Help sidebar lists topics under, in order.
enum HelpSection: String, CaseIterable {
    case basics = "Basics"
    case browsing = "Browsing"
    case files = "Working with Files"
    case connecting = "Connecting"
    case customizing = "Customizing"
}

/// A block of content within a help topic. Kept as a small native model
/// rather than a big Markdown blob — inline Markdown (`**bold**`, links)
/// renders fine in a `Text`, but block-level things like bullet lists and
/// tables don't, so those are their own cases, laid out as real views.
enum HelpBlock {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    /// (key combination, what it does)
    case shortcuts([(String, String)])
    /// (Windows term, its OneRoot/macOS counterpart)
    case terms([(String, String)])

    /// Every piece of text in the block, Markdown included.
    var texts: [String] {
        switch self {
        case .heading(let text), .paragraph(let text): return [text]
        case .bullets(let items): return items
        case .shortcuts(let rows), .terms(let rows): return rows.map { "\($0.0) \($0.1)" }
        }
    }
}

struct HelpTopic: Identifiable {
    let id: HelpTopicID
    let title: String
    let symbolName: String
    let section: HelpSection
    /// Words a reader might search for that the text doesn't use, such as
    /// Windows names ("Properties", "Recycle Bin"). Searched, not shown.
    var keywords: [String] = []
    let blocks: [HelpBlock]
    /// Related topics, shown as links at the end.
    var seeAlso: [HelpTopicID] = []
}
