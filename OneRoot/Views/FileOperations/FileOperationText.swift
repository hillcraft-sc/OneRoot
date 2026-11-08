import Foundation

/// The words for an operation's progress and outcome, shared by its
/// floating window and the File Operations card.
enum FileOperationText {
    /// "1.2 GB of 3.4 GB (85 MB/s) — About 2 minutes", "Preparing…", or
    /// time elapsed when the operation can't report bytes.
    static func status(for operation: FileOperationProgress, now: Date = Date()) -> String {
        if operation.isWaiting {
            return "Waiting for another copy to the same disk to finish\u{2026}"
        }
        if operation.isPreparing {
            return "Preparing\u{2026}"
        }
        if operation.isVerifying {
            return operation.isPaused ? "Paused \u{2014} verifying the copy" : "Verifying the copy\u{2026}"
        }
        guard !operation.isIndeterminate else {
            let time = "\(elapsed(operation.activeElapsed(at: now))) elapsed"
            return operation.isPaused ? "Paused \u{2014} \(time)" : time
        }
        var text = "\(bytes(operation.completedBytes)) of \(bytes(operation.totalBytes))"
        // No speed or time left while paused: nothing's moving.
        if operation.isPaused {
            return "Paused \u{2014} \(text)"
        }
        if let speed = speed(for: operation, now: now) {
            text += " (\(speed))"
        }
        if let eta = eta(for: operation, now: now) {
            text += " \u{2014} \(eta)"
        }
        return text
    }

    /// "Item 2 of 4: “photo.jpg”" — `nil` before the first item starts.
    static func currentItem(for operation: FileOperationProgress) -> String? {
        guard let name = operation.currentItemName else { return nil }
        guard operation.itemCount > 1 else { return "\u{201C}\(name)\u{201D}" }
        return "Item \(operation.currentItemIndex + 1) of \(operation.itemCount): \u{201C}\(name)\u{201D}"
    }

    /// "From ~/Downloads to ~/Talk", or whichever half is known.
    static func route(source: URL?, destination: URL?) -> String? {
        switch (source, destination) {
        case let (source?, destination?):
            return "From \(shortPath(source)) to \(shortPath(destination))"
        case let (nil, destination?):
            return "To \(shortPath(destination))"
        case let (source?, nil):
            return "From \(shortPath(source))"
        case (nil, nil):
            return nil
        }
    }

    /// "Done · 4 items, 3.4 GB in 42s · 9:29 AM",
    /// "Cancelled after 2 of 4 items · 1.1 GB of 3.4 GB · 9:29 AM".
    static func summary(for record: FileOperationRecord) -> String {
        let time = record.finishedAt.formatted(date: .omitted, time: .shortened)
        switch record.outcome {
        case .succeeded:
            var parts = [record.itemCount == 1 ? "1 item" : "\(record.itemCount) items"]
            if let total = record.totalBytes, total > 0 { parts.append(bytes(total)) }
            let took = record.duration >= 1 ? " in \(elapsed(record.duration))" : ""
            return "Done \u{00B7} \(parts.joined(separator: ", "))\(took) \u{00B7} \(time)"
        case .cancelled:
            return "Cancelled\(progress(record)) \u{00B7} \(time)"
        case .failed:
            return record.itemCount > 1
                ? "\(record.finishedItems) of \(record.itemCount) items done \u{00B7} \(time)"
                : "Failed\(progress(record)) \u{00B7} \(time)"
        }
    }

    /// " after 2 of 4 items · 1.1 GB of 3.4 GB", or "" when there's
    /// nothing to say.
    private static func progress(_ record: FileOperationRecord) -> String {
        var text = ""
        if record.itemCount > 1 {
            text = " after \(record.finishedItems) of \(record.itemCount) items"
        } else if record.duration >= 1 {
            text = " after \(elapsed(record.duration))"
        }
        if let total = record.totalBytes, total > 0 {
            text += " \u{00B7} \(bytes(record.completedBytes)) of \(bytes(total))"
        }
        return text
    }

    /// `~/Documents/Projects` rather than `/Users/…/Documents/Projects`.
    static func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        #if canImport(Darwin)
        return elapsedFormatter.string(from: max(interval, 0)) ?? "0s"
        #else
        return abbreviatedDuration(max(interval, 0))
        #endif
    }

    /// "1h 2m", "3m 20s", "45s": the two largest units, like
    /// `DateComponentsFormatter` (which swift-corelibs-foundation lacks).
    static func abbreviatedDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m" }
        return "\(seconds)s"
    }

    /// "2 minutes", "45 seconds": the time left, in its largest unit.
    static func spokenDuration(_ interval: TimeInterval) -> String {
        if interval < 60 {
            let seconds = max(1, Int(interval.rounded()))
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = max(1, Int((interval / 60).rounded()))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// The rate to show and project from: the last ten seconds' once
    /// there are a few seconds of readings (`recentRate`), the average so
    /// far until then. `nil` for the first moment.
    static func rate(for operation: FileOperationProgress, now: Date) -> Double? {
        if let recent = operation.recentRate {
            // No reading for a whole window: stalled, not still at the old speed.
            if let last = operation.rateSamples.last, now.timeIntervalSince(last.date) > FileOperationProgress.rateWindow { return 0 }
            return recent
        }
        let elapsed = operation.activeElapsed(at: now)
        guard elapsed >= 1, operation.completedBytes > 0 else { return nil }
        return Double(operation.completedBytes) / elapsed
    }

    /// Transfer rate, e.g. "85.2 MB/s"; nothing when nothing's moving.
    private static func speed(for operation: FileOperationProgress, now: Date) -> String? {
        guard let rate = rate(for: operation, now: now), rate >= 1 else { return nil }
        return bytes(Int64(rate)) + "/s"
    }

    /// Time left: what remains at the current rate. `nil` until there's
    /// enough progress (a few seconds and a few percent) for it to be
    /// steady, or while nothing's moving.
    private static func eta(for operation: FileOperationProgress, now: Date) -> String? {
        guard operation.completedBytes > 0, operation.totalBytes > operation.completedBytes else { return nil }
        let elapsed = operation.activeElapsed(at: now)
        let fraction = Double(operation.completedBytes) / Double(operation.totalBytes)
        guard elapsed >= 3, fraction >= 0.03, let rate = rate(for: operation, now: now), rate >= 1 else { return nil }
        let remaining = Double(operation.totalBytes - operation.completedBytes) / rate
        guard remaining.isFinite, remaining > 1 else { return nil }
        #if canImport(Darwin)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = remaining < 60 ? [.second] : [.minute]
        formatter.maximumUnitCount = 1
        guard let formatted = formatter.string(from: remaining) else { return nil }
        return "About \(formatted)"
        #else
        return "About \(spokenDuration(remaining))"
        #endif
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    #if canImport(Darwin)
    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter
    }()
    #endif
}
