#if os(Linux)
import Foundation
import Glibc

/// Linux's `FileWatching`: inotify. Unlike FSEvents it watches one folder
/// at a time, so the folders below each watched one are added too —
/// breadth-first, new ones as they appear — up to `folderLimit`, so a huge
/// tree can't use up the system's watches (shared by every app). Changes
/// are coalesced like `FileWatcher`'s: one `onChange` per burst, 300 ms
/// after the last event.
///
/// Adding the watches walks the tree, which touches every folder, so it runs
/// on a background queue (never the main thread: a big tree, or a network
/// share, would freeze the window), and a network filesystem (NFS, SMB,
/// FUSE) is watched at the top folder only: the kernel reports no changes
/// made from other machines there anyway.
final class InotifyWatcher: FileWatching {
    /// The most folders one watcher follows.
    static let folderLimit = 4_000

    var onChange: (@MainActor () -> Void)?

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    /// Guards `fd`, `paths` and `generation`, which the walking queue shares with the main thread.
    private let lock = NSLock()
    private var generation = 0
    private let walker = DispatchQueue(label: "com.oneroot.inotify-walk", qos: .utility)
    private var paths: [Int32: String] = [:]
    private var pendingPaths: Set<String> = []
    private var pendingSignal: DispatchWorkItem?
    private let limit: Int

    private static let mask: UInt32 = UInt32(IN_CREATE | IN_DELETE | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO
        | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR | IN_EXCL_UNLINK)

    init(folderLimit: Int = InotifyWatcher.folderLimit) {
        limit = folderLimit
    }

    deinit {
        stop()
    }

    func watch(_ urls: [URL]) {
        stop()
        guard !urls.isEmpty else { return }
        let descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard descriptor >= 0 else { return }
        lock.lock()
        fd = descriptor
        generation += 1
        let mine = generation
        lock.unlock()
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.readEvents() }
        source.resume()
        self.source = source
        let roots = urls.map(\.path)
        walker.async { [weak self] in self?.addTrees(roots, generation: mine) }
    }

    func stop() {
        pendingSignal?.cancel()
        pendingSignal = nil
        source?.cancel()
        source = nil
        lock.lock()
        generation += 1   // a walk still in progress gives up
        if fd >= 0 { close(fd) }
        fd = -1
        paths.removeAll()
        lock.unlock()
    }

    func drainChangedPaths() -> Set<String> {
        defer { pendingPaths.removeAll() }
        return pendingPaths
    }

    /// True when `path` is on a network filesystem (NFS, SMB/CIFS, sshfs,
    /// GVfs and the like), where walking a tree is slow and inotify can't see
    /// other machines' changes. Judged by the longest mount point that
    /// contains it in the kernel's mount table.
    static func isNetworkPath(_ path: String, in table: MountTable) -> Bool {
        let owner = table.entries
            .filter { $0.mountPoint == "/" || path == $0.mountPoint || path.hasPrefix($0.mountPoint + "/") }
            .max { $0.mountPoint.count < $1.mountPoint.count }
        guard let type = owner?.type else { return false }
        return LinuxVolumeRules.networkTypes.contains(type) || type == "fuse.gvfsd-fuse"
    }

    private static func isNetworkFilesystem(_ path: String) -> Bool {
        MountTable.current().map { isNetworkPath(path, in: $0) } ?? false
    }

    /// Watches each of `roots` and the folders below, breadth-first, within
    /// the limit (roots on a network filesystem: just the root). Symbolic
    /// links aren't followed. Runs on `walker`; stops if a newer `watch` or
    /// `stop` has replaced generation `mine`.
    private func addTrees(_ roots: [String], generation mine: Int) {
        let shallow = Set(roots.filter(Self.isNetworkFilesystem))
        var queue = roots[...]
        while let path = queue.popFirst() {
            lock.lock()
            let current = generation == mine && paths.count < limit
            var wd: Int32 = -1
            if current {
                wd = inotify_add_watch(fd, path, Self.mask)
                if wd >= 0 { paths[wd] = path }
            }
            lock.unlock()
            guard current else { return }
            guard wd >= 0, !shallow.contains(path) else { continue }
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
            for child in children {
                let childPath = path == "/" ? "/" + child : path + "/" + child
                var info = stat()
                if lstat(childPath, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR {
                    queue.append(childPath)
                }
            }
        }
    }

    private func readEvents() {
        let headerSize = MemoryLayout<inotify_event>.size
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var changed = false
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { break } // EAGAIN: all read
            var offset = 0
            while offset + headerSize <= count {
                let event = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: inotify_event.self) }
                let nameStart = offset + headerSize
                let nameEnd = min(nameStart + Int(event.len), count)
                let name = buffer[nameStart..<nameEnd].prefix { $0 != 0 }
                offset = nameEnd
                handle(event, name: String(decoding: name, as: UTF8.self))
                changed = true
            }
        }
        if changed { signal() }
    }

    private func handle(_ event: inotify_event, name: String) {
        let mask = event.mask
        if mask & UInt32(IN_IGNORED) != 0 {
            lock.lock(); paths.removeValue(forKey: event.wd); lock.unlock()
            return
        }
        if mask & UInt32(IN_Q_OVERFLOW) != 0 {
            // Too many at once: say "everything" changed.
            lock.lock(); let all = Array(paths.values); lock.unlock()
            pendingPaths.formUnion(all)
            return
        }
        lock.lock()
        let folder = paths[event.wd]
        let mine = generation
        lock.unlock()
        guard let folder else { return }
        let path = name.isEmpty ? folder : (folder == "/" ? "/" + name : folder + "/" + name)
        pendingPaths.insert(path)
        // A folder created or moved in: follow it too.
        if mask & UInt32(IN_ISDIR) != 0, mask & UInt32(IN_CREATE | IN_MOVED_TO) != 0 {
            walker.async { [weak self] in self?.addTrees([path], generation: mine) }
        }
    }

    private func signal() {
        pendingSignal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pendingSignal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
#endif
