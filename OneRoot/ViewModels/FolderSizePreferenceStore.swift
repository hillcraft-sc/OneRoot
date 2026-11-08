import Foundation
import Observation

/// Whether to calculate every folder's size automatically — Settings ▸
/// General ▸ Always calculate folder sizes. App-wide, like Show Hidden Files: every open
/// tab follows a change immediately.
@MainActor
@Observable
final class FolderSizePreferenceStore {
    static let shared = FolderSizePreferenceStore()
    private static let key = "com.oneroot.calculateAllFolderSizes"

    private(set) var calculateAll: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        calculateAll = defaults.bool(forKey: Self.key)
    }

    func toggle() {
        set(!calculateAll)
    }

    func set(_ value: Bool) {
        guard value != calculateAll else { return }
        calculateAll = value
        defaults.set(calculateAll, forKey: Self.key)
    }
}
