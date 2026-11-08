import Foundation
import Observation

/// What Combine's `$property.sink { … }` did, for `@Observable` types
/// (#80): calls `onChange` on the main actor with the new value whenever
/// something `read` touches changes — after the change has landed, once
/// per burst of changes in the same run-loop turn. Keep the returned watch;
/// releasing it, or `cancel()`, stops watching.
///
/// Works on macOS and Linux (Observation ships with Swift on both).
@MainActor
final class ObservationWatch {
    private var isCancelled = false

    /// `emitsInitialValue` calls `onChange` right away with the current
    /// value, as a Combine `sink` on `@Published` did.
    static func watch<Value>(
        _ read: @escaping @MainActor () -> Value,
        emitsInitialValue: Bool = true,
        onChange: @escaping @MainActor (Value) -> Void
    ) -> ObservationWatch {
        let watch = ObservationWatch()
        let initial = watch.track(read, onChange)
        if emitsInitialValue { onChange(initial) }
        return watch
    }

    func cancel() {
        isCancelled = true
    }

    /// Reads under observation and re-arms after each change (Observation
    /// reports a change once per registration, before it's applied — so
    /// the new value is read on the next turn).
    @discardableResult
    private func track<Value>(_ read: @escaping @MainActor () -> Value, _ onChange: @escaping @MainActor (Value) -> Void) -> Value {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.isCancelled else { return }
                    let value = self.track(read, onChange)
                    onChange(value)
                }
            }
        }
    }
}
