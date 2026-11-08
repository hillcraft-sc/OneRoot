import SwiftUI

/// The look shared by every icon button in the location and action bars,
/// and the pane toggles: monochrome glyph, no border, a soft rounded
/// highlight on hover and press, and a dimmed glyph while disabled. Color
/// is reserved for state — `isOn` (a pane that's showing) and `isDestructive`
/// (Trash, red only while hovered) — never for ordinary commands.
struct BarButtonStyle: ButtonStyle {
    var isOn = false
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        BarButtonBody(configuration: configuration, isOn: isOn, isDestructive: isDestructive)
    }
}

private struct BarButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isOn: Bool
    let isDestructive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(foreground)
            .frame(minWidth: 28, minHeight: 24)
            .padding(.horizontal, 2)
            // Its own size only — a bare `minWidth` frame would otherwise
            // stretch to soak up spare room in the row.
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovering = $0 }
    }

    private var foreground: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.tertiary) }
        if isDestructive, isHovering { return AnyShapeStyle(Color.red) }
        if isOn { return AnyShapeStyle(theme.accentColor) }
        return AnyShapeStyle(.primary)
    }

    private var background: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return Color.primary.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}
