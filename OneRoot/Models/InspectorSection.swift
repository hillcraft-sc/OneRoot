import Foundation

/// Which tab of details the Inspector shows. Kept per window tab (`Tab`)
/// and saved with the session.
enum InspectorSection: String, CaseIterable, Codable {
    case details, moreInfo, permissions

    var title: String {
        switch self {
        case .details: return "Details"
        case .moreInfo: return "More Info"
        case .permissions: return "Permissions"
        }
    }
}
