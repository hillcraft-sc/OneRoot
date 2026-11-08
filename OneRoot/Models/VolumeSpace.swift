import Foundation

/// Free/total byte counts for the volume containing some URL — see
/// `VolumeSpaceService`.
struct VolumeSpace: Equatable {
    let availableCapacity: Int64
    let totalCapacity: Int64
}

extension VolumeSpace {
    /// How full a disk is, for the storage bar's color: the accent color
    /// until 80% used, orange from 80%, red from 90% (#59).
    enum Level: Equatable {
        case normal, nearlyFull, full

        /// Said with the bar (VoiceOver), so the warning isn't in the
        /// color alone.
        var description: String? {
            switch self {
            case .normal: return nil
            case .nearlyFull: return "nearly full"
            case .full: return "almost out of space"
            }
        }
    }

    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(totalCapacity - availableCapacity) / Double(totalCapacity)
    }

    var level: Level {
        switch usedFraction {
        case 0.9...: return .full
        case 0.8...: return .nearlyFull
        default: return .normal
        }
    }
}
