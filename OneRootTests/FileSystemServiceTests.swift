import XCTest
@testable import OneRoot

final class FileSystemServiceTests: XCTestCase {
    private var service = FileSystemService()
    private var tempDirectory: URL!
    /// Where Replace sends the items it replaces, instead of the real Trash.
    private var fakeTrash: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        fakeTrash = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        service.trashItem = Self.fakeTrashItem(into: fakeTrash)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: fakeTrash)
    }

    static func fakeTrashItem(into trash: URL) -> @Sendable (URL) throws -> URL? {
        { url in
            let destination = trash.appendingPathComponent("\(UUID().uuidString) \(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func testFoldersSortBeforeFilesThenByName() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("m-folder"),
            withIntermediateDirectories: true
        )

        let nodes = try await service.listDirectory(tempDirectory)

        XCTAssertEqual(nodes.map(\.name), ["m-folder", "a.txt", "z.txt"])
        XCTAssertTrue(nodes[0].isDirectory)
        XCTAssertFalse(nodes[1].isDirectory)
    }

    func testHiddenFilesAreSkipped() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let nodes = try await service.listDirectory(tempDirectory)

        XCTAssertTrue(nodes.isEmpty)
    }

    func testHiddenFilesAreIncludedWhenRequested() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let nodes = try await service.listDirectory(tempDirectory, includeHidden: true)

        XCTAssertEqual(nodes.map(\.name), [".hidden"])
    }

    func testMissingDirectoryThrows() async {
        let missing = tempDirectory.appendingPathComponent("does-not-exist")

        do {
            _ = try await service.listDirectory(missing)
            XCTFail("expected listDirectory to throw for a missing path")
        } catch {
            XCTAssertTrue(error is FileSystemError)
        }
    }

    func testFileMetadataIsPopulated() async throws {
        let fileURL = tempDirectory.appendingPathComponent("data.txt")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        let nodes = try await service.listDirectory(tempDirectory)
        let node = try XCTUnwrap(nodes.first)

        XCTAssertEqual(node.name, "data.txt")
        XCTAssertFalse(node.isDirectory)
        XCTAssertEqual(node.size, 11)
        XCTAssertNotNil(node.modificationDate)
        XCTAssertNotNil(node.creationDate)
        XCTAssertEqual(node.fileExtension, "txt")
        XCTAssertEqual(node.tags, [])
    }

    func testAppBundleIsReportedAsAPackage() async throws {
        #if os(Linux)
        throw XCTSkip("Linux has no packages")
        #endif
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Example.app"),
            withIntermediateDirectories: true
        )

        let nodes = try await service.listDirectory(tempDirectory)
        let node = try XCTUnwrap(nodes.first)

        XCTAssertTrue(node.isDirectory)
        XCTAssertTrue(node.isPackage)
    }

    // MARK: Autocomplete

    func testSuggestFoldersReturnsOnlyFoldersSortedByName() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Zebra"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Apple"), withIntermediateDirectories: true)
        try "x".write(to: tempDirectory.appendingPathComponent("Middle.txt"), atomically: true, encoding: .utf8)

        let names = await service.suggestFolders(in: tempDirectory)

        XCTAssertEqual(names, ["Apple", "Zebra"])
    }

    func testSuggestFoldersForMissingDirectoryReturnsEmpty() async {
        let names = await service.suggestFolders(in: tempDirectory.appendingPathComponent("does-not-exist"))

        XCTAssertEqual(names, [])
    }

    // MARK: New Folder

    func testCreateFolderUsesRequestedName() async throws {
        let url = try await service.createFolder(named: "Docs", in: tempDirectory)

        XCTAssertEqual(url.lastPathComponent, "Docs")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateFolderAutoNumbersOnCollision() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Docs"), withIntermediateDirectories: true)

        let url = try await service.createFolder(named: "Docs", in: tempDirectory)

        XCTAssertEqual(url.lastPathComponent, "Docs (2)")
    }

    // MARK: New File

    func testCreateFileUsesRequestedNameAndIsEmpty() async throws {
        let url = try await service.createFile(named: "notes.txt", in: tempDirectory)

        XCTAssertEqual(url.lastPathComponent, "notes.txt")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testCreateFileAutoNumbersOnCollision() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let url = try await service.createFile(named: "notes.txt", in: tempDirectory)

        XCTAssertEqual(url.lastPathComponent, "notes (2).txt")
    }

    // MARK: Rename

    func testRenameMovesToNewName() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        try "x".write(to: original, atomically: true, encoding: .utf8)

        let renamed = try await service.rename(original, to: "new.txt")

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameThrowsWhenDestinationExists() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        try "x".write(to: original, atomically: true, encoding: .utf8)
        try "x".write(to: tempDirectory.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        do {
            _ = try await service.rename(original, to: "new.txt")
            XCTFail("expected rename to throw for an existing destination")
        } catch {
            guard case FileSystemError.alreadyExists = error else {
                return XCTFail("expected .alreadyExists, got \(error)")
            }
        }
    }

    // MARK: Move to Trash

    func testMoveToTrashRemovesItemsFromTheirOriginalLocation() async throws {
        let fileURL = tempDirectory.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        await service.moveToTrash([fileURL])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMoveToTrashReturnsWhereEachItemLanded() async throws {
        let fileURL = tempDirectory.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = await service.moveToTrash([fileURL])

        let trashedURL = try XCTUnwrap(result.locations[fileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
    }

    func testMoveToTrashGoesOnPastAnItemItCannotTrash() async throws {
        let missing = tempDirectory.appendingPathComponent("missing.txt")
        let fileURL = tempDirectory.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = await service.moveToTrash([missing, fileURL])

        XCTAssertEqual(result.trashed, [fileURL])
        XCTAssertEqual(result.failures.map(\.url), [missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: Restore

    func testRestoreFromTrashMovesItemBackToDestination() async throws {
        let fileURL = tempDirectory.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let result = await service.moveToTrash([fileURL])
        let trashedURL = try XCTUnwrap(result.locations[fileURL])

        try await service.restoreFromTrash(trashedURL, to: fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: trashedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: Delete Permanently

    func testDeletePermanentlyRemovesTheItem() async throws {
        let fileURL = tempDirectory.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        try await service.deletePermanently([fileURL])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeletePermanentlyRemovesAFolderWithReadOnlySubfolders() async throws {
        let outer = tempDirectory.appendingPathComponent("cache", isDirectory: true)
        let locked = outer.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        try await service.deletePermanently([outer])

        XCTAssertFalse(FileManager.default.fileExists(atPath: outer.path))
    }

    // MARK: Copy

    func testCopyItemsCopiesWithoutRemovingSource() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("a.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        try await service.copyItems([fileURL], to: destDir) { _ in .skip }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
    }

    func testCopyItemsSkipsOnConflictWhenResolutionIsSkip() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "source".write(to: fileURL, atomically: true, encoding: .utf8)
        try "existing".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        try await service.copyItems([fileURL], to: destDir) { _ in .skip }

        let contents = try String(contentsOf: destDir.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "existing") // untouched, since we skipped
    }

    func testCopyItemsReplacesOnConflictWhenResolutionIsReplace() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "source".write(to: fileURL, atomically: true, encoding: .utf8)
        try "existing".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        try await service.copyItems([fileURL], to: destDir) { _ in .replace }

        let contents = try String(contentsOf: destDir.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(contents, "source")
    }

    func testCopyItemsKeepsBothOnConflictWhenResolutionIsKeepBoth() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "source".write(to: fileURL, atomically: true, encoding: .utf8)
        try "existing".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        try await service.copyItems([fileURL], to: destDir) { _ in .keepBoth }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a (2).txt").path))
    }

    // MARK: Replace safety (#22)

    func testCopyIntoSameFolderDuplicatesWithoutAskingAndKeepsOriginal() async throws {
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        var conflictAsked = false

        // Answering Replace here used to delete the original before copying it onto itself.
        try await service.copyItems([fileURL], to: tempDirectory) { _ in conflictAsked = true; return .replace }

        XCTAssertFalse(conflictAsked, "a file pasted into its own folder isn't a conflict")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: tempDirectory.appendingPathComponent("a (2).txt"), encoding: .utf8), "original")
    }

    func testCopyIntoSameFolderSpelledThroughASymlinkIsStillTheSameFolder() async throws {
        let realDir = tempDirectory.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let link = tempDirectory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDir)
        let fileURL = realDir.appendingPathComponent("a.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        try await service.copyItems([fileURL], to: link) { _ in .replace }

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: realDir.appendingPathComponent("a (2).txt").path))
    }

    func testMoveIntoSameFolderIsANoOp() async throws {
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        var conflictAsked = false

        try await service.moveItems([fileURL], to: tempDirectory) { _ in conflictAsked = true; return .replace }

        XCTAssertFalse(conflictAsked)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(names, ["a.txt"], "nothing should be created or left behind")
    }

    func testReplaceKeepsOriginalWhenTheCopyFails() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let existing = destDir.appendingPathComponent("a.txt")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        // An unreadable source makes the copy itself fail.
        let source = tempDirectory.appendingPathComponent("a.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path) }

        do {
            try await service.copyItems([source], to: destDir) { _ in .replace }
            XCTFail("copying an unreadable file should throw")
        } catch {}

        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
        let names = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
        XCTAssertEqual(names, ["a.txt"], "no staging leftovers")
    }

    func testReplaceFolderSwapsInNewContentsRatherThanMerging() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        let existingFolder = destDir.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "old".write(to: existingFolder.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        let sourceFolder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try "new".write(to: sourceFolder.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        try await service.copyItems([sourceFolder], to: destDir) { _ in .replace }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existingFolder.path), ["new.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destDir.path), ["Folder"], "no staging leftovers")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFolder.path), "a copy leaves the source alone")
    }

    func testMoveWithReplaceRemovesSourceAndReplacesDestination() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "existing".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let source = tempDirectory.appendingPathComponent("a.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)

        try await service.moveItems([source], to: destDir) { _ in .replace }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destDir.appendingPathComponent("a.txt"), encoding: .utf8), "source")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destDir.path), ["a.txt"])
    }

    func testCopyingAFolderIntoItsOwnSubfolderThrowsWithoutTouchingAnything() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let sub = folder.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        do {
            try await service.copyItems([folder], to: sub) { _ in .keepBoth }
            XCTFail("expected cannotPlaceInsideItself")
        } catch FileSystemError.cannotPlaceInsideItself {}

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sub.path), [])
    }

    func testReplacingAFolderThatContainsTheSourceThrowsAndLeavesSourceIntact() async throws {
        // Copying Photos/Photos up into Photos' parent, then choosing
        // Replace, would delete the source's own parent folder.
        let outer = tempDirectory.appendingPathComponent("Photos", isDirectory: true)
        let inner = outer.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "keep".write(to: inner.appendingPathComponent("pic.txt"), atomically: true, encoding: .utf8)

        do {
            try await service.moveItems([inner], to: tempDirectory) { _ in .replace }
            XCTFail("expected cannotReplaceContainingItem")
        } catch FileSystemError.cannotReplaceContainingItem {}

        XCTAssertEqual(try String(contentsOf: inner.appendingPathComponent("pic.txt"), encoding: .utf8), "keep")
    }

    // MARK: Change log (for Undo)

    func testChangeLogRecordsCopiesAndMoves() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let a = tempDirectory.appendingPathComponent("a.txt")
        let b = tempDirectory.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let copyLog = FileChangeLog()
        try await service.copyItems([a], to: destDir, changeLog: copyLog) { _ in .skip }
        let moveLog = FileChangeLog()
        try await service.moveItems([b], to: destDir, changeLog: moveLog) { _ in .skip }

        XCTAssertEqual(copyLog.changes, [.created(destDir.appendingPathComponent("a.txt"))])
        XCTAssertEqual(moveLog.changes, [.moved(from: b, to: destDir.appendingPathComponent("b.txt"))])
    }

    func testChangeLogKeepsItemsThatFinishedBeforeAFailure() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let good = tempDirectory.appendingPathComponent("good.txt")
        try "x".write(to: good, atomically: true, encoding: .utf8)
        let unreadable = tempDirectory.appendingPathComponent("unreadable.txt")
        try "x".write(to: unreadable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }

        let log = FileChangeLog()
        do {
            try await service.copyItems([good, unreadable], to: destDir, changeLog: log) { _ in .skip }
            XCTFail("copying an unreadable file should throw")
        } catch {}

        XCTAssertEqual(log.changes, [.created(destDir.appendingPathComponent("good.txt"))])
    }

    func testChangeLogSkipsSkippedItems() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let source = tempDirectory.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let log = FileChangeLog()
        try await service.copyItems([source], to: destDir, changeLog: log) { _ in .skip }

        XCTAssertEqual(log.changes, [])
    }

    // MARK: Move

    func testMoveItemsRemovesSource() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        try await service.moveItems([fileURL], to: destDir) { _ in .skip }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
    }

    // MARK: totalSize

    func testTotalSizeOfURLsSumsFilesRecursively() async throws {
        try "12345".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8) // 5 bytes
        let sub = tempDirectory.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "1234567890".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8) // 10 bytes

        let total = await service.totalSize(of: [
            tempDirectory.appendingPathComponent("a.txt"),
            tempDirectory.appendingPathComponent("sub", isDirectory: true),
        ])

        XCTAssertEqual(total, 15)
    }

    func testTotalSizeOfMissingURLIsZeroNotAnError() async {
        let total = await service.totalSize(of: [tempDirectory.appendingPathComponent("does-not-exist")])

        XCTAssertEqual(total, 0)
    }

    // MARK: Progress reporting

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testCopyItemsLeavesNoProgressEntryBehindOnceItFinishes() async throws {
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let before = await FileOperationProgressCenter.shared.operations.count

        try await service.copyItems([fileURL], to: destDir) { _ in .skip }

        let after = await FileOperationProgressCenter.shared.operations.count
        XCTAssertEqual(after, before, "the progress popup's entry should be removed once the copy finishes")
    }
    #endif
}
