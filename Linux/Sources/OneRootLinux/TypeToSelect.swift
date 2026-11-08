import Foundation

/// The "type a few letters to jump to a file" buffer. Display-free so it can
/// be tested: letters typed within `timeout` of each other build one prefix;
/// a pause starts over. Pressing the same letter again cycles through the
/// names that start with it.
struct TypeToSelect {
    static let timeout: TimeInterval = 1.0

    private(set) var buffer = ""
    private var lastTyped: Date?

    /// Adds a typed character and returns the prefix to look for.
    mutating func type(_ character: Character, at time: Date = Date()) -> String {
        if let lastTyped, time.timeIntervalSince(lastTyped) > Self.timeout { buffer = "" }
        buffer.append(character)
        lastTyped = time
        return buffer
    }

    mutating func reset() {
        buffer = ""
        lastTyped = nil
    }

    /// Index of the name to select, or nil. Starts at `current` so typing
    /// further letters stays on a match that still fits; a repeated single
    /// letter moves on to the next match.
    static func match(prefix: String, in names: [String], current: Int?) -> Int? {
        guard !prefix.isEmpty, !names.isEmpty else { return nil }
        let lowered = prefix.lowercased()
        func fits(_ index: Int) -> Bool {
            names[index].lowercased().hasPrefix(lowered)
        }
        let repeated = lowered.count > 1 && Set(lowered).count == 1
        if repeated, let first = lowered.first {
            // "aa" means "the next name starting with a".
            return cycle(String(first), in: names, after: current)
        }
        if let current, current < names.count, fits(current) { return current }
        return names.indices.first(where: fits)
    }

    private static func cycle(_ letter: String, in names: [String], after current: Int?) -> Int? {
        let start = (current ?? -1) + 1
        let order = Array(start..<names.count) + Array(0..<min(start, names.count))
        return order.first { names[$0].lowercased().hasPrefix(letter) }
    }
}
