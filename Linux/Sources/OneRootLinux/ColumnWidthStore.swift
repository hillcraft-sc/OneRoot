import Foundation
@testable import OneRoot

/// Remembered widths of the file list's columns (every pane, tab and window
/// shares them, like column visibility). Name stretches and has none.
@MainActor
final class ColumnWidthStore {
    static let shared = ColumnWidthStore()
    static let key = "com.oneroot.linux.columnWidths"
    static let range = 40...1200

    private let defaults: UserDefaults
    private var widths: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        widths = (defaults.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
    }

    func width(for column: FileColumn) -> Int? {
        widths[column.rawValue].map(Self.clamped)
    }

    func set(_ width: Int, for column: FileColumn) {
        let clamped = Self.clamped(width)
        guard column != .name, widths[column.rawValue] != clamped else { return }
        widths[column.rawValue] = clamped
        defaults.set(widths, forKey: Self.key)
    }

    nonisolated static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
