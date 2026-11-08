import Foundation
import Observation

/// Carries a folder's filter into Advanced Search (Search Subfolders).
/// Advanced Search is a single window that may already be open, so rather
/// than a value passed when opening it, it watches this and takes what's
/// waiting — whether it was just opened or brought to the front.
@MainActor
@Observable
final class SearchHandoffCenter {
    static let shared = SearchHandoffCenter()

    private(set) var pending: SearchCriteria?

    /// For tests; the app uses `shared`.
    init() {}

    func hand(_ criteria: SearchCriteria) {
        pending = criteria
    }

    /// The waiting criteria, once — `nil` if there are none.
    func take() -> SearchCriteria? {
        defer { pending = nil }
        return pending
    }
}
