import Foundation
import Observation
@testable import OneRoot

/// The Grid view's icon size, shared by every pane and remembered (the Mac's
/// `com.oneroot.iconSize` range, 48-256). The Linux default stays at 64.
@MainActor
@Observable
final class GridIconSize {
    static let shared = GridIconSize()
    static let defaultSize = 64
    static let range = Int(FileViewMode.iconSizeRange.lowerBound)...Int(FileViewMode.iconSizeRange.upperBound)

    private(set) var size: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: FileViewMode.iconSizeKey) as? Double
        size = Self.clamped(saved.map { Int($0) } ?? Self.defaultSize)
    }

    func set(_ value: Int) {
        let clamped = Self.clamped(value)
        guard clamped != size else { return }
        size = clamped
        defaults.set(Double(clamped), forKey: FileViewMode.iconSizeKey)
    }

    nonisolated static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
