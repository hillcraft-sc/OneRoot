import AppKit

/// A table/outline row that draws a theme's selection color. With no custom
/// selection color (the native themes) it defers entirely to AppKit, so
/// macOS's own accent-colored selection is untouched.
///
/// A themed selection is a quiet tint behind text that keeps its normal
/// color, unlike the system's solid accent with text flipping to white — so
/// `interiorBackgroundStyle` is pinned to `.normal`, which is what stops
/// AppKit flipping the cell's text color.
final class ThemedRowView: NSTableRowView {
    var selectionColor: NSColor?

    override func drawSelection(in dirtyRect: NSRect) {
        guard let selectionColor else {
            super.drawSelection(in: dirtyRect)
            return
        }
        // Dimmer while the window isn't active, as the system's is.
        selectionColor.withAlphaComponent(isEmphasized ? 1 : 0.65).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        selectionColor == nil ? super.interiorBackgroundStyle : .normal
    }
}

/// A column header drawn in the theme's bar color and text color. Native
/// themes use AppKit's own header untouched.
final class ThemedHeaderCell: NSTableHeaderCell {
    var theme = ThemeCatalog.nativeDark

    override var attributedStringValue: NSAttributedString {
        get {
            guard let surfaces = theme.surfaces else { return super.attributedStringValue }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            return NSAttributedString(string: stringValue, attributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: surfaces.secondaryText.nsColor,
                .paragraphStyle: style,
            ])
        }
        set { super.attributedStringValue = newValue }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let surfaces = theme.surfaces else {
            super.draw(withFrame: cellFrame, in: controlView)
            return
        }
        surfaces.bar.nsColor.setFill()
        cellFrame.fill()
        surfaces.separator.nsColor.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 4, width: 1, height: max(cellFrame.height - 8, 0)).fill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        // Centered vertically: the header is taller than one line of
        // text, and the interior would otherwise sit against its top.
        let textHeight = ceil(attributedStringValue.size().height)
        let interior = NSRect(
            x: cellFrame.minX + 4,
            y: (cellFrame.midY - textHeight / 2 - 0.5).rounded(),
            width: max(cellFrame.width - 8, 0),
            height: textHeight
        )
        drawInterior(withFrame: interior, in: controlView)
    }
}
