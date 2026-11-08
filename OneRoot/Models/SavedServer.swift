import Foundation

/// A network address saved to the "Favorite Servers" list in Connect to
/// Server, so it can be reconnected with a click instead of retyping.
struct SavedServer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: URL

    init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
