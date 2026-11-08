import AppKit
import SwiftUI

/// What's behind everything in a main window: macOS's translucent sidebar
/// material for the OneRoot look (it falls back to opaque by itself under
/// Reduce Transparency), or the theme's sidebar color for the others.
struct WindowBackdrop: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.usesMaterialBackdrop {
            // Frosted, and in light mode washed toward white — the airy
            // look of the design rather than the system sidebar's gray.
            VisualEffectBackground(material: .sidebar)
                .overlay(theme.isDark ? Color.white.opacity(0.02) : Color.white.opacity(0.5))
        } else {
            (theme.surfaces?.sidebar.color ?? Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

extension View {
    /// A content card: the theme's content color, rounded, with a hairline
    /// edge and a faint shadow, floating on the window backdrop.
    /// `squareTopLeading` for the card the tab strip sits on, so the tabs and
    /// the card read as one panel rather than tabs perched on a rounded corner.
    func card(cornerRadius: CGFloat = 12, squareTopLeading: Bool = false) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, squareTopLeading: squareTopLeading))
    }
}

private struct CardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let squareTopLeading: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: squareTopLeading ? 0 : cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
        content
            .background(theme.contentBackgroundColor, in: shape)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(theme.separatorColor, lineWidth: contrast == .increased ? 1 : 0.5)
            )
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.07), radius: 6, y: 1)
    }
}

