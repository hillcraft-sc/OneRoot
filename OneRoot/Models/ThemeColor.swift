import Foundation

/// An sRGB color, kept as plain numbers so themes stay Foundation-only (the
/// view layer turns these into `Color`/`NSColor` — see `ThemeStyle.swift`).
struct ThemeColor: Equatable, Hashable {
    /// 0...1 each.
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`, the way every theme's own documentation writes colors.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var hexString: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// WCAG relative luminance (0 black ... 1 white).
    var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1 (identical) ... 21 (black on white). Text wants
    /// 4.5+, icons and other graphics 3+.
    func contrast(with other: ThemeColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This color, unchanged if it already has at least `minimum` contrast
    /// against every one of `backgrounds` — otherwise moved toward black (on
    /// light backgrounds) or white (on dark ones) by the smallest amount that
    /// does. How a palette's official color is kept wherever it's legible and
    /// only nudged where it isn't (see `ThemeCatalog.themed`).
    func ensuringContrast(_ minimum: Double, against backgrounds: [ThemeColor]) -> ThemeColor {
        func passes(_ color: ThemeColor) -> Bool { backgrounds.allSatisfy { color.contrast(with: $0) >= minimum } }
        guard !passes(self), let first = backgrounds.first else { return self }
        let target = first.relativeLuminance > 0.5 ? ThemeColor(hex: 0x000000) : ThemeColor(hex: 0xFFFFFF)
        for step in 1...100 {
            let candidate = blended(with: target, amount: Double(step) / 100)
            if passes(candidate) { return candidate }
        }
        return target
    }

    /// This color moved `amount` (0...1) of the way toward `other`.
    func blended(with other: ThemeColor, amount: Double) -> ThemeColor {
        ThemeColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }
}
