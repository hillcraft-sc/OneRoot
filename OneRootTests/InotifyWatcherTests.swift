#if os(Linux)
import XCTest
@testable import OneRoot

final class InotifyWatcherTests: XCTestCase {
    private let table = MountTable(parsing: """
        /dev/sda1 / ext4 rw 0 0
        nas:/export /mnt/nas nfs4 rw 0 0
        //pc/share /mnt/share cifs rw 0 0
        gvfsd-fuse /run/user/1000/gvfs fuse.gvfsd-fuse rw 0 0
        /dev/sdb1 /mnt/nas-backup ext4 rw 0 0
        """)

    func testPathsOnNetworkMountsAreNetworkPaths() {
        XCTAssertTrue(InotifyWatcher.isNetworkPath("/mnt/nas", in: table))
        XCTAssertTrue(InotifyWatcher.isNetworkPath("/mnt/nas/photos/2024", in: table))
        XCTAssertTrue(InotifyWatcher.isNetworkPath("/mnt/share/docs", in: table))
        XCTAssertTrue(InotifyWatcher.isNetworkPath("/run/user/1000/gvfs/sftp:host=x", in: table))
    }

    func testLocalPathsAndLookalikeNamesAreNot() {
        XCTAssertFalse(InotifyWatcher.isNetworkPath("/home/me", in: table))
        XCTAssertFalse(InotifyWatcher.isNetworkPath("/mnt/nas-backup/files", in: table))
        XCTAssertFalse(InotifyWatcher.isNetworkPath("/mnt/nasty", in: table))
    }

    @MainActor
    func testWatchReturnsAtOnceAndStillReportsChangesInSubfolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let watcher = InotifyWatcher()
        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        watcher.onChange = { changed.fulfill() }
        watcher.watch([root])
        try await Task.sleep(nanoseconds: 500_000_000)   // the walk runs in the background
        try Data("x".utf8).write(to: sub.appendingPathComponent("file.txt"))
        await fulfillment(of: [changed], timeout: 5)
        watcher.stop()
    }
}
#endif
