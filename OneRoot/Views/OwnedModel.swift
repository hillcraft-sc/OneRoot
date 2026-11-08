import SwiftUI

/// Holds a view's own `@Observable` model, created once.
///
/// `@State private var model = Model()` builds a new `Model` every time the
/// view's struct is re-created, and keeps only the first — so any work the
/// initializer does (reading the disk, starting a file watcher) runs again
/// for nothing. `@StateObject` takes its value as an autoclosure and builds
/// it once; this wrapper lets an `@Observable` model use that, while views
/// still observe the model's own properties, not this box (which never
/// changes).
///
///     @StateObject private var owned = OwnedModel(Model())
///     private var model: Model { owned.value }
final class OwnedModel<Value: AnyObject>: ObservableObject {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
