import Foundation

/// How the address bar shows the current location — Settings ▸ General.
/// Stored with `@AppStorage(AddressBarStyle.storageKey)`, so every window's
/// address bar follows a change immediately.
enum AddressBarStyle: String, CaseIterable {
    /// Clickable segments, Explorer-style; click the empty space (or ⇧⌘G)
    /// to type. The default.
    case breadcrumbs
    /// Always a text field, as before breadcrumbs existed.
    case textField

    static let storageKey = "com.oneroot.addressBarStyle"

    var title: String {
        switch self {
        case .breadcrumbs: return "Clickable path"
        case .textField: return "Text field"
        }
    }
}
