import Foundation

/// Chart colors for Visualize, the Mac's palette: a colorblind-safe
/// categorical set used in a fixed order (a kind of file keeps its color
/// whatever its size), an ordered blue ramp for age, and a neutral gray for
/// "Other", unknown and untagged. Each has a light and a dark step. Color
/// never carries meaning alone: every chart sits beside a labeled list.
enum ChartPalette {
    enum Color: Equatable {
        case series(Int)
        /// Step `step` of `count` on the ramp; lightest is the newest.
        case ordinal(step: Int, of: Int)
        case neutral
    }

    static let seriesLight: [UInt32] = [0x2a78d6, 0xeb6834, 0x1baf7a, 0xeda100, 0xe87ba4, 0x008300, 0x6250d6, 0xe34948]
    static let seriesDark: [UInt32] = [0x3987e5, 0xd95926, 0x199e70, 0xc98500, 0xd55181, 0x008300, 0x9085e9, 0xe66767]
    static let rampLight: [UInt32] = [0x86b6ef, 0x5598e7, 0x2a78d6, 0x1c5cab]
    static let rampDark: [UInt32] = [0x184f95, 0x256abf, 0x3987e5, 0x6da7ec]
    static let neutralLight: UInt32 = 0xb4b2ac
    static let neutralDark: UInt32 = 0x6b6a66

    /// The color for the `index`th category, never cycled: past the set it
    /// is neutral.
    static func series(at index: Int) -> Color {
        index < seriesLight.count ? .series(index) : .neutral
    }

    static func rampPosition(step: Int, of count: Int) -> Int {
        guard count > 1 else { return 0 }
        let position = Int((Double(step) / Double(count - 1) * Double(rampLight.count - 1)).rounded())
        return min(max(position, 0), rampLight.count - 1)
    }

    static func hex(_ color: Color, dark: Bool) -> UInt32 {
        switch color {
        case .series(let index):
            let set = dark ? seriesDark : seriesLight
            return set[min(max(index, 0), set.count - 1)]
        case .ordinal(let step, let count):
            return (dark ? rampDark : rampLight)[rampPosition(step: step, of: count)]
        case .neutral:
            return dark ? neutralDark : neutralLight
        }
    }

    /// The CSS class that paints `color`, for the light or dark scheme.
    static func className(_ color: Color, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        switch color {
        case .series(let index): return "oneroot-chart-s\(min(max(index, 0), seriesLight.count - 1))-\(scheme)"
        case .ordinal(let step, let count): return "oneroot-chart-o\(rampPosition(step: step, of: count))-\(scheme)"
        case .neutral: return "oneroot-chart-n-\(scheme)"
        }
    }

    /// The rules for every class `className` can return.
    static var css: String {
        func rule(_ name: String, _ hex: UInt32) -> String {
            String(format: "    .%@ { background-color: #%06x; }\n", name, hex)
        }
        var out = ""
        for dark in [false, true] {
            for index in 0..<seriesLight.count { out += rule(className(.series(index), dark: dark), hex(.series(index), dark: dark)) }
            for position in 0..<rampLight.count {
                out += rule(className(.ordinal(step: position, of: rampLight.count), dark: dark), (dark ? rampDark : rampLight)[position])
            }
            out += rule(className(.neutral, dark: dark), hex(.neutral, dark: dark))
        }
        return out
    }
}
