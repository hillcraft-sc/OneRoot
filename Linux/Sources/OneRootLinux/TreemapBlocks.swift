import Foundation
@testable import OneRoot

/// The blocks of the Folders treemap, as the Mac's chart picks them: the
/// biggest items (at most `maxBlocks`, none under `minShare` of the total),
/// with everything smaller folded into one "Other" block so each block is
/// big enough to read and click. Display-free so it can be tested.
struct TreemapBlocks {
    struct Block: Equatable {
        /// nil for the folded "Other" block.
        let entry: StorageEntry?
        let otherCount: Int
        let size: Int64

        var title: String { entry?.name ?? "Other (\(otherCount))" }
        var isFolder: Bool { entry?.isDirectory ?? false }
    }

    static let maxBlocks = 14
    static let minShare = 0.01

    static func blocks(children: [StorageEntry], totalSize: Int64) -> [Block] {
        let entries = children.filter { $0.size > 0 }
        let minimum = Int64(Double(totalSize) * minShare)
        let shown = entries.prefix(maxBlocks).prefix { $0.size >= minimum }
        var result = shown.map { Block(entry: $0, otherCount: 0, size: $0.size) }
        let rest = entries.dropFirst(shown.count)
        if !rest.isEmpty {
            result.append(Block(entry: nil, otherCount: rest.count, size: rest.reduce(0) { $0 + $1.size }))
        }
        return result
    }

    /// "12%", or "<1%" for a sliver; "" when nothing is counted.
    static func percent(_ size: Int64, of total: Int64) -> String {
        guard total > 0 else { return "" }
        let value = Double(size) / Double(total) * 100
        return value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }
}
