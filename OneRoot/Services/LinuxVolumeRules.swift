import Foundation

/// Which of Linux's mounts the sidebar shows, and how. The mount table
/// lists dozens of the system's own (/proc, /sys, tmpfs, cgroups, snaps);
/// people care about: the root file system, drives the desktop mounted
/// (/media, /run/media/$USER), ones mounted by hand under /mnt, and network
/// shares. Plain rules over a `MountTable`, so they're tested anywhere.
enum LinuxVolumeRules {
    static let networkTypes: Set<String> = ["cifs", "smb3", "smbfs", "nfs", "nfs4", "fuse.sshfs", "sshfs", "afs", "9p", "fuse.rclone", "davfs", "fuse.davfs2"]

    /// Never shown, wherever they're mounted.
    static let systemTypes: Set<String> = [
        "proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "securityfs", "cgroup", "cgroup2", "pstore", "bpf",
        "debugfs", "tracefs", "configfs", "fusectl", "mqueue", "hugetlbfs", "autofs", "binfmt_misc", "efivarfs",
        "squashfs", "overlay", "nsfs", "rpc_pipefs", "fuse.portal", "fuse.gvfsd-fuse", "ramfs",
    ]

    struct Mount: Equatable {
        let mountPoint: String
        let device: String
        let type: String
        let name: String
        /// Plugged in (USB, SD card) or a share: offered for Eject.
        let isEjectable: Bool
        let isNetwork: Bool
    }

    /// The mounts worth showing, root first, then by name; one per mount
    /// point (the last mounted wins, as the kernel does).
    static func mounts(in table: MountTable) -> [Mount] {
        var byPoint: [String: Mount] = [:]
        for entry in table.entries {
            guard let mount = mount(for: entry) else { continue }
            byPoint[mount.mountPoint] = mount
        }
        return byPoint.values.sorted { lhs, rhs in
            if lhs.mountPoint == "/" { return rhs.mountPoint != "/" }
            if rhs.mountPoint == "/" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func mount(for entry: MountTable.Entry) -> Mount? {
        let point = entry.mountPoint
        guard !systemTypes.contains(entry.type) else { return nil }
        let isNetwork = networkTypes.contains(entry.type) || entry.device.hasPrefix("//")
        let isDesktopDrive = point.hasPrefix("/media/") || point.hasPrefix("/run/media/")
        let isManual = point.hasPrefix("/mnt/")
        guard point == "/" || isDesktopDrive || isManual || isNetwork else { return nil }
        // A share mounted somewhere like /proc… is still nothing to show.
        for hidden in ["/proc", "/sys", "/dev", "/run/user", "/snap", "/boot", "/var/lib"] where point == hidden || point.hasPrefix(hidden + "/") {
            return nil
        }
        let name = point == "/" ? "File System" : (point as NSString).lastPathComponent
        return Mount(
            mountPoint: point,
            device: entry.device,
            type: entry.type,
            name: name,
            isEjectable: isDesktopDrive || isNetwork,
            isNetwork: isNetwork
        )
    }
}
