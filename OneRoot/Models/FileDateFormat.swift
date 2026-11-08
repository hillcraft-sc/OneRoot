import Foundation

/// How OneRoot shows a file's dates, everywhere — the file list's date
/// columns, the Inspector, search results. Settings ▸ General ▸
/// "Friendly dates" turns on Finder's form ("Today at 5:57
/// PM", "Yesterday at 9:17 PM"); older dates read the same either way
/// ("Oct 28, 2026 at 8:30 AM"). Exports and Terminal commands keep plain
/// dates, since they're read elsewhere.
enum FileDateFormat {
    static let usesRelativeDatesKey = "com.oneroot.dates.usesRelative"

    static func string(from date: Date, defaults: UserDefaults = .standard) -> String {
        guard defaults.bool(forKey: usesRelativeDatesKey) else { return plain.string(from: date) }
        #if canImport(Darwin)
        return relative.string(from: date)
        #else
        // Linux's DateFormatter ignores `doesRelativeDateFormatting`.
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday" : nil
        guard let day else { return plain.string(from: date) }
        return "\(day) at \(time.string(from: date))"
        #endif
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
