import Foundation

/// How a folder's contents are shown — remembered per folder (see
/// `FolderViewModeService`), like Explorer's and Finder's view settings.
enum FileViewMode: String, CaseIterable {
    case list
    case icons

    /// Icon edge length for `.icons`, app-wide (the status bar's slider) —
    /// `@AppStorage(FileViewMode.iconSizeKey)`.
    static let iconSizeKey = "com.oneroot.iconSize"
    static let defaultIconSize: Double = 96
    static let iconSizeRange: ClosedRange<Double> = 48...256

    var title: String {
        switch self {
        case .list: return "as List"
        case .icons: return "as Icons"
        }
    }
}
