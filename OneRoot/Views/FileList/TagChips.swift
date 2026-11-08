import AppKit
import SwiftUI

/// Finder tag colors. macOS exposes the standard tags' names and colors
/// (`NSWorkspace.fileLabels`/`fileLabelColors` — Red, Orange, …, in the
/// user's language); a custom tag's color isn't readable by other apps, so
/// those show neutral gray rather than a guessed color.
enum TagColors {
    static func color(for tag: String) -> NSColor {
        let labels = NSWorkspace.shared.fileLabels
        let colors = NSWorkspace.shared.fileLabelColors
        // Index 0 is "None".
        if let index = labels.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }),
           index > 0, index < colors.count {
            return colors[index]
        }
        return .systemGray
    }
}

/// One tag as a soft capsule with a colored dot — the file list's Tags
/// column and the Inspector.
struct TagChip: View {
    let tag: String

    var body: some View {
        let color = Color(nsColor: TagColors.color(for: tag))
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(tag)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag \(tag)")
    }
}

/// The Tags column's cell: the same chips, drawn directly so a long list
/// scrolls as fast as plain text would.
final class TagChipsCellView: NSTableCellView {
    var tags: [String] = [] {
        didSet {
            guard tags != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(tags.isEmpty ? nil : "Tags: " + tags.joined(separator: ", "))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.systemFont(ofSize: 11)
        var x: CGFloat = 2
        let height: CGFloat = 18
        let y = (bounds.height - height) / 2
        for tag in tags {
            let color = TagColors.color(for: tag)
            let text = NSAttributedString(string: tag, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            let width = ceil(text.size().width) + 7 + 6 + 4 + 7
            guard x + width <= bounds.width else { break }
            let chip = NSRect(x: x, y: y, width: width, height: height)
            color.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: chip, xRadius: height / 2, yRadius: height / 2).fill()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: chip.minX + 7, y: chip.midY - 3, width: 6, height: 6)).fill()
            text.draw(at: NSPoint(x: chip.minX + 7 + 6 + 4, y: chip.midY - text.size().height / 2))
            x += width + 4
        }
    }
}
