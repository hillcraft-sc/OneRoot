import SwiftUI

/// Chart colors for Visualize. The categorical set is a validated
/// colorblind-safe palette, used in its fixed order (a kind of file keeps
/// its color whatever its size), stepped separately for light and dark.
/// Three light steps are under 3:1 against the card, so every chart sits
/// beside a labeled list — color never carries meaning alone.
enum VisualizePalette {
    private static let light: [UInt32] = [0x2a78d6, 0xeb6834, 0x1baf7a, 0xeda100, 0xe87ba4, 0x008300, 0x6250d6, 0xe34948]
    private static let dark: [UInt32] = [0x3987e5, 0xd95926, 0x199e70, 0xc98500, 0xd55181, 0x008300, 0x9085e9, 0xe66767]

    /// Categorical slot `index` (0-based, fixed order — never cycled).
    static func series(_ index: Int, dark isDark: Bool) -> Color {
        let colors = isDark ? dark : light
        return Color(hex: colors[min(index, colors.count - 1)])
    }

    /// Ordered steps of one hue (blue), lightest = least, for age: newest
    /// to oldest reads light to dark. Kept at least 2:1 against the card.
    static func ordinal(_ step: Int, of count: Int, dark isDark: Bool) -> Color {
        let ramp: [UInt32] = isDark
            ? [0x184f95, 0x256abf, 0x3987e5, 0x6da7ec]
            : [0x86b6ef, 0x5598e7, 0x2a78d6, 0x1c5cab]
        let position = count <= 1 ? 0 : Int((Double(step) / Double(count - 1) * Double(ramp.count - 1)).rounded())
        return Color(hex: ramp[min(max(position, 0), ramp.count - 1)])
    }

    /// For "Other", unknown, and untagged: present but not an identity.
    static func neutral(dark isDark: Bool) -> Color {
        Color(hex: isDark ? 0x6b6a66 : 0xb4b2ac)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
