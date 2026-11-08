import AppKit

/// How Compare Panes' statuses look in the file list and the compare bar:
/// a short word, a color, and a sentence for the tooltip and VoiceOver.
/// Color is never the only signal — the word is always there.
enum ComparisonStatusStyle {
    static func label(_ status: ComparisonStatus) -> String {
        switch status {
        case .same: return ""
        case .onlyHere: return "Only here"
        case .newerHere: return "Newer"
        case .olderHere: return "Older"
        case .differs: return "Differs"
        }
    }

    static func color(_ status: ComparisonStatus) -> NSColor {
        switch status {
        case .same: return .secondaryLabelColor
        case .onlyHere: return .controlAccentColor
        case .newerHere: return readable(.systemGreen)
        case .olderHere: return .secondaryLabelColor
        case .differs: return readable(.systemOrange)
        }
    }

    /// The system green and orange are too light to read as small text on
    /// white, so in light appearances (and with Increase Contrast) they're
    /// darkened; dark appearances use them as they are.
    private static func readable(_ color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
                .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
            return isDark ? color : (color.blended(withFraction: 0.4, of: .black) ?? color)
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
}
