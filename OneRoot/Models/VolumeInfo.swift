import Foundation

/// A mounted volume — internal disk, external/USB drive, disk image, or
/// (from Phase 6 on) a mounted network share.
struct VolumeInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isEjectable: Bool
    let availableCapacity: Int64?
    let totalCapacity: Int64?
    /// `false` for network shares (SMB/AFP/NFS) — used to pick a network
    /// vs. local-drive icon in the sidebar. Defaults to `true` so existing
    /// call sites (tests) don't need updating.
    let isLocal: Bool

    init(
        url: URL,
        name: String,
        isRemovable: Bool,
        isEjectable: Bool,
        availableCapacity: Int64?,
        totalCapacity: Int64?,
        isLocal: Bool = true
    ) {
        self.url = url
        self.name = name
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.availableCapacity = availableCapacity
        self.totalCapacity = totalCapacity
        self.isLocal = isLocal
    }

    var id: URL { url }
}
