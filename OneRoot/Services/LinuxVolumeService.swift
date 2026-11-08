#if os(Linux)
import Foundation
import Glibc

/// Linux's `VolumeProviding`: the mounts `LinuxVolumeRules` picks from the
/// kernel's mount table, with free space from `statvfs`, kept current by
/// waiting on /proc/self/mounts (the kernel flags it on every mount and
/// unmount). Ejects the way the desktop does: `udisksctl` for drives it
/// mounted, `gio` or `umount` for others.
struct LinuxVolumeService: VolumeProviding {
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject {
        let monitor = MountMonitor()
        let report = {
            let volumes = Self.currentVolumes()
            DispatchQueue.main.async { MainActor.assumeIsolated { onChange(volumes) } }
        }
        monitor.start(onChange: report)
        return monitor
    }

    /// Reads the mounts and their sizes — off the main actor: a share that
    /// stopped answering can make `statvfs` wait.
    static func currentVolumes() -> [VolumeInfo] {
        guard let table = MountTable.current() else { return [] }
        return LinuxVolumeRules.mounts(in: table).map { mount in
            var info = statvfs()
            let hasSize = statvfs(mount.mountPoint, &info) == 0
            let blockSize = Int64(info.f_frsize == 0 ? info.f_bsize : info.f_frsize)
            return VolumeInfo(
                url: URL(fileURLWithPath: mount.mountPoint, isDirectory: true),
                name: mount.name,
                isRemovable: mount.isEjectable && !mount.isNetwork,
                isEjectable: mount.isEjectable,
                availableCapacity: hasSize ? Int64(info.f_bavail) * blockSize : nil,
                totalCapacity: hasSize ? Int64(info.f_blocks) * blockSize : nil,
                isLocal: !mount.isNetwork
            )
        }
    }

    /// Unmounts the way each kind of mount needs, most specific tool first:
    /// drives the desktop mounted go through udisks; GVfs/FUSE mounts through
    /// `gio`; anything the kernel mounted (an NFS or SMB share from `mount`)
    /// through `umount`, and when that needs root, once more through
    /// `pkexec` (the desktop's own password prompt). Every step has a time
    /// limit so a share that stopped answering can't hold the eject forever.
    /// Run this off the main thread.
    func lastEjectFailure() -> String? { Self.failures.value }

    private static let failures = FailureNote()

    @discardableResult
    func eject(_ volume: VolumeInfo) -> Bool {
        Self.failures.value = nil
        guard let table = MountTable.current(),
              let mount = LinuxVolumeRules.mounts(in: table).first(where: { $0.mountPoint == volume.url.path }) else { return false }
        if mount.device.hasPrefix("/dev/") {
            // Unmount, then power the drive off so it's safe to unplug.
            guard Self.run("udisksctl", ["unmount", "--block-device", mount.device, "--no-user-interaction"]) else {
                return Self.run("umount", [mount.mountPoint]) || Self.run("pkexec", ["umount", mount.mountPoint], seconds: 120)
            }
            _ = Self.run("udisksctl", ["power-off", "--block-device", mount.device, "--no-user-interaction"])
            return true
        }
        if mount.type.hasPrefix("fuse") {
            return Self.run("gio", ["mount", "--unmount", mount.mountPoint]) || Self.run("umount", [mount.mountPoint])
        }
        // A plain kernel mount; if it's busy or needs root, say so rather than hanging.
        return Self.run("umount", [mount.mountPoint]) || Self.run("pkexec", ["umount", mount.mountPoint], seconds: 120)
    }

    /// Runs a tool found on PATH; `true` when it succeeded within `seconds`.
    /// A tool still running at the limit is stopped.
    private static func run(_ tool: String, _ arguments: [String], seconds: Double = 20) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        // The tool's own complaint ("target is busy", "must be superuser") is
        // what the user needs to see, so keep it.
        let errors = FileManager.default.temporaryDirectory.appendingPathComponent("oneroot-eject-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errors) }
        process.standardError = try? FileHandle(forWritingTo: errors)
        do {
            try process.run()
        } catch {
            failures.value = "\(tool) isn\u{2019}t installed"
            return false
        }
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                failures.value = "\(tool) didn\u{2019}t finish in \(Int(seconds)) seconds"
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus != 0 else { return true }
        let text = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        failures.value = text.isEmpty ? "\(tool) exited with status \(process.terminationStatus)" : "\(tool): \(text)"
        return false
    }
}

/// The last unmount tool's complaint, shared between the eject (background
/// thread) and the message built after it.
private final class FailureNote: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return text }
        set { lock.lock(); text = newValue; lock.unlock() }
    }
}

/// Waits on /proc/self/mounts on a background thread and calls back once
/// right away and after every change, until this token is released. The
/// thread holds only the flag, never the token.
private final class MountMonitor {
    private let stop = CancellationFlag()

    func start(onChange: @escaping @Sendable () -> Void) {
        let stop = self.stop
        Thread.detachNewThread {
            onChange()
            let fd = open("/proc/self/mounts", O_RDONLY)
            guard fd >= 0 else { return }
            defer { close(fd) }
            var poller = pollfd(fd: fd, events: Int16(POLLPRI), revents: 0)
            while !stop.isCancelled {
                // A second at a time, so a released monitor ends promptly.
                let ready = poll(&poller, 1, 1_000)
                guard ready > 0, poller.revents & Int16(POLLERR | POLLPRI) != 0, !stop.isCancelled else { continue }
                // Re-arm: the flag clears once the file is read again.
                lseek(fd, 0, SEEK_SET)
                var scratch = [UInt8](repeating: 0, count: 4096)
                while read(fd, &scratch, scratch.count) > 0 {}
                onChange()
            }
        }
    }

    deinit {
        stop.cancel()
    }
}
#endif
