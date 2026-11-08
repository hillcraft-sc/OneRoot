#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Squarified treemap layout (Bruls, Huizing & van Wijk): rectangles with
/// areas proportional to `values`, kept as close to square as possible so
/// they're easy to compare and to click. Pure geometry; `values` should be
/// sorted largest first. Zero and negative values get no rectangle.
enum TreemapLayout {
    static func rects(for values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = values.map { max($0, 0) * scale }

        var remaining = bounds
        var row: [Int] = []
        var index = 0
        while index < areas.count {
            if areas[index] <= 0 { index += 1; continue }
            let side = Double(min(remaining.width, remaining.height))
            let candidate = row + [index]
            if row.isEmpty || worst(candidate.map { areas[$0] }, side: side) <= worst(row.map { areas[$0] }, side: side) {
                row = candidate
                index += 1
            } else {
                remaining = place(row, areas: areas, in: remaining, into: &result)
                row = []
            }
        }
        if !row.isEmpty { _ = place(row, areas: areas, in: remaining, into: &result) }
        return result
    }

    /// The worst aspect ratio in a row of `areas` laid along `side`.
    private static func worst(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0, let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }

    /// Lays `row` along the shorter side of `bounds`; returns what's left.
    private static func place(_ row: [Int], areas: [Double], in bounds: CGRect, into result: inout [CGRect]) -> CGRect {
        let sum = row.reduce(0) { $0 + areas[$1] }
        if bounds.width >= bounds.height {
            // A column down the left edge.
            let width = CGFloat(sum / Double(bounds.height))
            var y = bounds.minY
            for item in row {
                let height = CGFloat(areas[item]) / width
                result[item] = CGRect(x: bounds.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: bounds.minX + width, y: bounds.minY, width: max(bounds.width - width, 0), height: bounds.height)
        } else {
            // A row along the top edge.
            let height = CGFloat(sum / Double(bounds.width))
            var x = bounds.minX
            for item in row {
                let width = CGFloat(areas[item]) / height
                result[item] = CGRect(x: x, y: bounds.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: bounds.minX, y: bounds.minY + height, width: bounds.width, height: max(bounds.height - height, 0))
        }
    }
}
