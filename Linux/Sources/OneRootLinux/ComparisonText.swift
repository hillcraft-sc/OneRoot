import Foundation
@testable import OneRoot

/// The words Compare Panes uses in the list, the bar and the preview.
/// Display-free so it can be tested. The word is always shown; the CSS
/// class only adds color.
enum ComparisonText {
    static func label(_ status: ComparisonStatus) -> String {
        switch status {
        case .same: return ""
        case .onlyHere: return "Only here"
        case .newerHere: return "Newer"
        case .olderHere: return "Older"
        case .differs: return "Differs"
        }
    }

    static func explanation(_ status: ComparisonStatus) -> String {
        switch status {
        case .same: return "The same in both panes"
        case .onlyHere: return "Not in the other pane"
        case .newerHere: return "Newer here (for a folder: has newer or extra items inside)"
        case .olderHere: return "Newer in the other pane"
        case .differs: return "Changed on both sides, or the same date with a different size"
        }
    }

    static func cssClass(_ status: ComparisonStatus) -> String? {
        switch status {
        case .same, .olderHere: return nil
        case .onlyHere: return "oneroot-cmp-only"
        case .newerHere: return "oneroot-cmp-newer"
        case .differs: return "oneroot-cmp-differs"
        }
    }

    /// "3 newer · 2 only here · 1 differs", or the empty-handed wording.
    static func summary(_ result: FolderComparison, onLeft: Bool) -> String {
        let parts = [ComparisonStatus.newerHere, .onlyHere, .differs]
            .map { ($0, result.count($0, onLeft: onLeft)) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \(label($0.0).lowercased())" }
        return parts.isEmpty ? "nothing newer or extra" : parts.joined(separator: " \u{00B7} ")
    }

    static func progress(scanned: Int) -> String {
        scanned > 0 ? "Comparing\u{2026} \(scanned) items" : "Comparing\u{2026}"
    }

    /// Heading and body of the Copy to Left/Right preview.
    static func syncPreview(_ plan: PaneComparison.SyncPlan, sourceName: String, destinationName: String, listLimit: Int = 12) -> (heading: String, body: String) {
        guard !plan.items.isEmpty else {
            return ("Nothing to copy to \u{201C}\(destinationName)\u{201D}", notCopiedLine(plan) ?? "")
        }
        let count = plan.items.count == 1 ? "1 item" : "\(plan.items.count) items"
        var lines = ["Copies what\u{2019}s newer or missing. Folders are merged. Nothing is deleted, nothing newer in \u{201C}\(destinationName)\u{201D} is overwritten, and replaced files go to the Trash.", ""]
        for url in plan.items.prefix(listLimit) {
            let status = plan.statuses[url.lastPathComponent].map(label) ?? ""
            lines.append(status.isEmpty ? "\u{2022} \(url.lastPathComponent)" : "\u{2022} \(url.lastPathComponent) (\(status))")
        }
        if plan.items.count > listLimit { lines.append("\u{2026}and \(plan.items.count - listLimit) more") }
        if let note = notCopiedLine(plan) { lines += ["", note] }
        return ("Copy \(count) from \u{201C}\(sourceName)\u{201D} to \u{201C}\(destinationName)\u{201D}?", lines.joined(separator: "\n"))
    }

    private static func notCopiedLine(_ plan: PaneComparison.SyncPlan) -> String? {
        guard !plan.notCopied.isEmpty else { return nil }
        let shown = plan.notCopied.prefix(5).joined(separator: ", ")
        let more = plan.notCopied.count > 5 ? ", and \(plan.notCopied.count - 5) more" : ""
        return "Not copied (changed on both sides, or the same date with a different size): \(shown)\(more)"
    }
}
