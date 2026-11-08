import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Small pieces the search editors share.
@MainActor
enum SearchInputHelpers {
    /// "Regex Suggestions": a button listing the Mac's starter patterns;
    /// choosing one fills the field (which stays editable).
    static func regexSuggestionsButton(onPick: @escaping @MainActor (String) -> Void) -> Button {
        let button = Button(label: "Regex Suggestions\u{2026}")
        button.tooltipText = "Common patterns to start from"
        button.onClicked { [weak button] in
            guard let button else { return }
            let items = RegexSuggestion.all.map { suggestion in
                LocationListPopover.Item(suggestion.name) { onPick(suggestion.pattern) }
            }
            LocationListPopover.show(items, from: button, label: "Regex Suggestions")
        }
        return button
    }

    /// A date typed as YYYY-MM-DD (local time, start of that day), or nil.
    nonisolated static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 10 else { return nil }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar.current
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return calendar.startOfDay(for: date)
    }

    nonisolated static func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
