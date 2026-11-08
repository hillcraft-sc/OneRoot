import XCTest
@testable import OneRoot

/// The freedesktop.org Trash (Linux's), against a Trash in a temp folder.
final class FreedesktopTrashTests: XCTestCase {
    private var root: URL!
    private var trash: FreedesktopTrash!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let date = self.date
        trash = FreedesktopTrash(
            homeTrash: root.appendingPathComponent("data/Trash", isDirectory: true),
            mountPoint: { _ in "/" },
            userID: 1000,
            now: { date }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEnsureHomeTrashExistsMakesFilesAndInfoPrivately() throws {
        trash.ensureHomeTrashExists()
        for name in ["files", "info"] {
            let path = root.appendingPathComponent("data/Trash/\(name)").path
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), name)
            XCTAssertTrue(isDirectory.boolValue)
        }
        trash.ensureHomeTrashExists() // again: no error, nothing disturbed
    }

    func testTrashingMovesTheItemAndWritesWhereItCameFrom() throws {
        let file = try write("docs/My Report #1.txt")

        let trashed = try trash.trash(file)

        XCTAssertEqual(trashed.path, root.appendingPathComponent("data/Trash/files/My Report #1.txt").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
        let info = try String(contentsOf: root.appendingPathComponent("data/Trash/info/My Report #1.txt.trashinfo"), encoding: .utf8)
        XCTAssertTrue(info.hasPrefix("[Trash Info]\n"))
        XCTAssertTrue(info.contains("Path=\(file.path.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "#", with: "%23"))\n"), info)
        XCTAssertTrue(info.contains("DeletionDate=20"))
        XCTAssertEqual(trash.originalLocation(of: trashed)?.path, file.path)
    }

    func testSameNameGetsANumberBeforeTheExtension() throws {
        let first = try trash.trash(try write("docs/a.txt"))
        let second = try trash.trash(try write("docs/a.txt"))
        let third = try trash.trash(try write("docs/a.txt"))

        XCTAssertEqual([first, second, third].map(\.lastPathComponent), ["a.txt", "a.2.txt", "a.3.txt"])
        XCTAssertEqual(trash.originalLocation(of: third)?.lastPathComponent, "a.txt")
    }

    func testFoldersAndForgetting() throws {
        let folder = root.appendingPathComponent("docs/Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("docs/Project/inside.txt")

        let trashed = try trash.trash(folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.appendingPathComponent("inside.txt").path))

        trash.forget(trashed)
        XCTAssertNil(trash.originalLocation(of: trashed))
    }

    func testMissingItemThrows() {
        XCTAssertThrowsError(try trash.trash(root.appendingPathComponent("docs/gone.txt")))
    }

    func testDriveTrashRecordsPathsRelativeToTheDrivesTop() throws {
        // As another app (or OneRoot) leaves it on a USB drive.
        let drive = root.appendingPathComponent("media/USB", isDirectory: true)
        let files = drive.appendingPathComponent(".Trash-1000/files", isDirectory: true)
        let info = drive.appendingPathComponent(".Trash-1000/info", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try "x".write(to: files.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)
        try "[Trash Info]\nPath=Pictures/Summer%202026/photo.jpg\nDeletionDate=2026-11-01T10:00:00\n"
            .write(to: info.appendingPathComponent("photo.jpg.trashinfo"), atomically: true, encoding: .utf8)

        let origin = trash.originalLocation(of: files.appendingPathComponent("photo.jpg"))

        XCTAssertEqual(origin?.path, drive.appendingPathComponent("Pictures/Summer 2026/photo.jpg").path)
    }

    func testWhichFoldersAreTrashes() {
        XCTAssertTrue(FreedesktopTrash.isTrashFiles(URL(fileURLWithPath: "/home/eric/.local/share/Trash/files")))
        XCTAssertTrue(FreedesktopTrash.isTrashFiles(URL(fileURLWithPath: "/media/USB/.Trash-1000/files")))
        XCTAssertTrue(FreedesktopTrash.isTrashFiles(URL(fileURLWithPath: "/media/USB/.Trash/1000/files")))
        XCTAssertFalse(FreedesktopTrash.isTrashFiles(URL(fileURLWithPath: "/home/eric/files")))
        XCTAssertFalse(FreedesktopTrash.isTrashFiles(URL(fileURLWithPath: "/home/eric/.local/share/Trash")))
    }

    func testPathEncodingRoundTrips() {
        let path = "/home/eric/Résumé 100% final?.txt"
        let encoded = FreedesktopTrash.encode(path)
        XCTAssertFalse(encoded.contains(" "))
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertEqual(FreedesktopTrash.decode(encoded), path)
    }
}

final class MountTableTests: XCTestCase {
    private let table = MountTable(parsing: """
        /dev/nvme0n1p2 / ext4 rw,relatime 0 0
        /dev/nvme0n1p1 /boot vfat rw 0 0
        /dev/sda1 /run/media/eric/My\\040Drive exfat rw,nosuid 0 0
        //nas/share /mnt/nas cifs rw 0 0
        """)

    func testParsesAndUnescapes() {
        XCTAssertEqual(table.entries.count, 4)
        XCTAssertEqual(table.entries[2].mountPoint, "/run/media/eric/My Drive")
        XCTAssertEqual(table.entries[2].type, "exfat")
    }

    func testFindsTheLongestContainingMount() {
        XCTAssertEqual(table.entry(containing: "/run/media/eric/My Drive/photos/a.jpg")?.type, "exfat")
        XCTAssertEqual(table.entry(containing: "/boot/efi")?.mountPoint, "/boot")
        XCTAssertEqual(table.entry(containing: "/bootstrap")?.mountPoint, "/", "a name that only starts the same isn't inside")
        XCTAssertEqual(table.entry(containing: "/mnt/nas")?.type, "cifs")
    }
}

/// Which Linux mounts the sidebar shows.
final class LinuxVolumeRulesTests: XCTestCase {
    private let table = MountTable(parsing: """
        proc /proc proc rw 0 0
        sysfs /sys sysfs rw 0 0
        /dev/nvme0n1p2 / btrfs rw 0 0
        /dev/nvme0n1p2 /home btrfs rw 0 0
        /dev/nvme0n1p1 /boot vfat rw 0 0
        tmpfs /run/user/1000 tmpfs rw 0 0
        gvfsd-fuse /run/user/1000/gvfs fuse.gvfsd-fuse rw 0 0
        /dev/loop3 /snap/firefox/1234 squashfs ro 0 0
        /dev/sdb1 /run/media/eric/USB\\040STICK exfat rw 0 0
        /dev/sdc1 /media/eric/SD vfat rw 0 0
        /dev/sdd1 /mnt/backup ext4 rw 0 0
        //nas/photos /mnt/nas cifs rw 0 0
        nas:/export /srv/nfs nfs4 rw 0 0
        overlay /var/lib/docker/overlay2/x/merged overlay rw 0 0
        """)

    func testShowsRootDrivesAndSharesOnly() {
        let mounts = LinuxVolumeRules.mounts(in: table)

        XCTAssertEqual(mounts.map(\.mountPoint), ["/", "/mnt/backup", "/mnt/nas", "/srv/nfs", "/media/eric/SD", "/run/media/eric/USB STICK"])
        XCTAssertEqual(mounts.first?.name, "File System")
        XCTAssertEqual(mounts.first { $0.mountPoint.hasSuffix("STICK") }?.name, "USB STICK")
    }

    func testWhatCanBeEjected() {
        let byPoint = Dictionary(uniqueKeysWithValues: LinuxVolumeRules.mounts(in: table).map { ($0.mountPoint, $0) })

        XCTAssertEqual(byPoint["/"]?.isEjectable, false)
        XCTAssertEqual(byPoint["/mnt/backup"]?.isEjectable, false, "mounted by hand: not the desktop's to eject")
        XCTAssertEqual(byPoint["/media/eric/SD"]?.isEjectable, true)
        XCTAssertEqual(byPoint["/mnt/nas"]?.isEjectable, true)
        XCTAssertEqual(byPoint["/mnt/nas"]?.isNetwork, true)
        XCTAssertEqual(byPoint["/srv/nfs"]?.isNetwork, true)
        XCTAssertEqual(byPoint["/media/eric/SD"]?.isNetwork, false)
    }

    #if os(Linux)
    func testThisMachinesVolumesIncludeTheRootAndArriveRightAway() {
        XCTAssertEqual(LinuxVolumeService.currentVolumes().first?.url.path, "/")
        XCTAssertNotNil(LinuxVolumeService.currentVolumes().first?.totalCapacity)

        let delivered = expectation(description: "the first list arrives")
        delivered.assertForOverFulfill = false
        var token: AnyObject? = LinuxVolumeService().monitorVolumes { volumes in
            if volumes.contains(where: { $0.url.path == "/" }) { delivered.fulfill() }
        }
        wait(for: [delivered], timeout: 5)
        XCTAssertNotNil(token)
        token = nil
    }
    #endif
}

#if os(Linux)
final class ProcFileTests: XCTestCase {
    func testReadsAProcFileToTheEnd() throws {
        let whole = try XCTUnwrap(MountTable.readWholeFile("/proc/self/mounts"))
        // Compare with the shell's view, which reads to EOF.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.arguments = ["/proc/self/mounts"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(whole.split(separator: "\n").count, String(decoding: data, as: UTF8.self).split(separator: "\n").count)
    }
}
#endif

/// Tags the way the Linux desktops keep them, and the extended attributes
/// under them.
final class XDGTagsTests: XCTestCase {
    func testParsesKDEsCommaList() {
        XCTAssertEqual(XDGTags.parse("Work, Urgent,,Red "), ["Work", "Urgent", "Red"])
        XCTAssertEqual(XDGTags.parse(""), [])
    }

    func testExtendedAttributesRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let name = "user.oneroot.test"
        do {
            try ExtendedAttributes.set(Data("hello".utf8), name, of: file.path)
        } catch {
            throw XCTSkip("this file system keeps no extended attributes: \(error)")
        }
        XCTAssertEqual(ExtendedAttributes.data(name, of: file.path), Data("hello".utf8))
        XCTAssertTrue(ExtendedAttributes.names(of: file.path).contains(name))
        try ExtendedAttributes.remove(name, of: file.path)
        XCTAssertNil(ExtendedAttributes.data(name, of: file.path))
        XCTAssertNoThrow(try ExtendedAttributes.remove(name, of: file.path), "removing what isn't there is fine")
    }

    #if os(Linux)
    func testTagsWrittenAsKDEReadsThem() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        try TagService().setTags(["Work", "Red"], on: file)

        XCTAssertEqual(ExtendedAttributes.data("user.xdg.tags", of: file.path).map { String(decoding: $0, as: UTF8.self) }, "Work,Red")
        XCTAssertEqual(try TagService().tags(of: file), ["Work", "Red"])
        XCTAssertEqual(FileSystemService.makeNode(for: file).tags, ["Work", "Red"])
        try TagService().setTags([], on: file)
        XCTAssertNil(ExtendedAttributes.data("user.xdg.tags", of: file.path))
    }
    #endif
}

/// File types from a shared MIME database (a small one, in a temp folder).
final class MimeDatabaseTests: XCTestCase {
    private var root: URL!
    private var database: MimeDatabase!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("image"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("application"), withIntermediateDirectories: true)
        try """
            # generated
            50:image/png:*.png
            50:application/gzip:*.gz
            50:application/x-compressed-tar:*.tar.gz
            50:text/x-makefile:makefile
            10:application/x-foo:*.png
            """.write(to: root.appendingPathComponent("globs2"), atomically: true, encoding: .utf8)
        try """
            <?xml version="1.0" encoding="utf-8"?>
            <mime-type xmlns="http://www.freedesktop.org/standards/shared-mime-info" type="image/png">
              <comment>PNG image</comment>
              <comment xml:lang="de">PNG-Bild</comment>
            </mime-type>
            """.write(to: root.appendingPathComponent("image/png.xml"), atomically: true, encoding: .utf8)
        database = MimeDatabase(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTypesByExtensionNameAndWeight() {
        XCTAssertEqual(database.type(forFileName: "Photo.PNG"), "image/png", "case doesn't matter; the heavier glob wins")
        XCTAssertEqual(database.type(forFileName: "backup.tar.gz"), "application/x-compressed-tar", "the longest extension first")
        XCTAssertEqual(database.type(forFileName: "notes.gz"), "application/gzip")
        XCTAssertEqual(database.type(forFileName: "Makefile"), "text/x-makefile")
        XCTAssertNil(database.type(forFileName: "README"))
    }

    func testKinds() {
        XCTAssertEqual(database.kind(forFileName: "a.png", isDirectory: false), "PNG image")
        XCTAssertEqual(database.kind(forFileName: "a.gz", isDirectory: false), "application/gzip", "no description file: the type itself")
        XCTAssertEqual(database.kind(forFileName: "data.xyz", isDirectory: false), "XYZ file")
        XCTAssertEqual(database.kind(forFileName: "Photos", isDirectory: true), "Folder")
    }

    func testCategories() {
        XCTAssertEqual(StorageCategory.of(mimeType: "image/png"), .images)
        XCTAssertEqual(StorageCategory.of(mimeType: "application/x-compressed-tar"), .archives)
        XCTAssertEqual(StorageCategory.of(mimeType: "application/pdf"), .documents)
        XCTAssertEqual(StorageCategory.of(mimeType: "text/x-python"), .code)
        XCTAssertNil(StorageCategory.of(mimeType: "application/octet-stream"))
    }

    #if os(Linux)
    func testThisMachinesDatabase() {
        XCTAssertEqual(MimeDatabase.shared.type(forFileName: "photo.png"), "image/png")
        XCTAssertEqual(FileSystemService.makeNode(for: URL(fileURLWithPath: "/etc")).kind, "Folder")
    }
    #endif
}
