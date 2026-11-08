import Foundation

/// A named, saved `SearchCriteria` — lets a common Advanced Search be
/// re-run without re-entering every filter. See `SavedSearchQueriesService`.
struct SavedSearchQuery: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var criteria: SearchCriteria

    init(id: UUID = UUID(), name: String, criteria: SearchCriteria) {
        self.id = id
        self.name = name
        self.criteria = criteria
    }
}
