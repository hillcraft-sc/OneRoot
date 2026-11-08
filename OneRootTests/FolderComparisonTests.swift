import XCTest
@testable import OneRoot

/// Compare Panes (#63): the comparison itself, what Copy to the other side
/// sends, and the automatic conflict answers it copies with.
final class FolderComparisonTests: XCTestCase {
    private var service = FileSystemService()
    private var tempDirectory: URL!
    private var left: URL!
    private var right: URL!
    private var fakeTrash: URL!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        left = tempDirectory.appendingPathComponent("Left", isDirectory: true)
        right = tempDirectory.appendingPathComponent("Right", isDirectory: true)
        fakeTrash = tempDirectory.appendingPathComponent("trash", isDirectory: true)
        for folder in [left!, right!, fakeTrash!] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        service.trashItem = FileSystemServiceTests.fakeTrashItem(into: fakeTrash)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Writes `text` at `path` under `folder`, modified `minutes` after `base`.
    @discardableResult
    private func write(_ text: String, _ path: String, in folder: URL, minutes: Double = 0) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(minutes * 60)], ofItemAtPath: url.path)
        return url
    }

    private func compare() async throws -> FolderComparison {
        try await FolderComparisonService().compare(left, right, cancellation: CancellationFlag())
    }

    // MARK: Comparing

    func testFileStatusesOnBothSides() async throws {
        try write("same", "same.txt", in: left)
        try write("same", "same.txt", in: right)
        try write("new", "edited.txt", in: left, minutes: 10)
        try write("old", "edited.txt", in: right)
        try write("x", "leftOnly.txt", in: left)
        try write("x", "rightOnly.txt", in: right)
        try write("short", "sized.txt", in: left)
        try write("longer", "sized.txt", in: right)

        let result = try await compare()

        XCTAssertEqual(result.left, ["same.txt": .same, "edited.txt": .newerHere, "leftOnly.txt": .onlyHere, "sized.txt": .differs])
        XCTAssertEqual(result.right, ["same.txt": .same, "edited.txt": .olderHere, "rightOnly.txt": .onlyHere, "sized.txt": .differs])
        XCTAssertFalse(result.isIdentical)
        XCTAssertEqual(result.count(.onlyHere, onLeft: true), 1)
    }

    func testTimestampsWithinASecondCountAsSame() async throws {
        try write("a", "a.txt", in: left)
        let other = try write("a", "a.txt", in: right)
        try FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(0.6)], ofItemAtPath: other.path)

        let result = try await compare()

        XCTAssertEqual(result.left["a.txt"], .same)
        XCTAssertTrue(result.isIdentical)
    }

    func testFoldersSumUpWhatsInside() async throws {
        // Ahead: only the left has newer/extra things.
        try write("new", "Ahead/a.txt", in: left, minutes: 5)
        try write("old", "Ahead/a.txt", in: right)
        try write("extra", "Ahead/deep/b.txt", in: left)
        try FileManager.default.createDirectory(at: right.appendingPathComponent("Ahead/deep"), withIntermediateDirectories: true)
        // Mixed: each side has something the other doesn't.
        try write("l", "Mixed/l.txt", in: left)
        try write("r", "Mixed/r.txt", in: right)
        // Same: identical contents, ignoring Finder's .DS_Store.
        try write("s", "Same/s.txt", in: left)
        try write("s", "Same/s.txt", in: right)
        try write("view settings", "Same/.DS_Store", in: left)

        let result = try await compare()

        XCTAssertEqual(result.left["Ahead"], .newerHere)
        XCTAssertEqual(result.right["Ahead"], .olderHere)
        XCTAssertEqual(result.left["Mixed"], .differs)
        XCTAssertEqual(result.right["Mixed"], .differs)
        XCTAssertEqual(result.left["Same"], .same)
    }

    func testAFileAgainstAFolderDiffers() async throws {
        try write("x", "thing", in: left)
        try FileManager.default.createDirectory(at: right.appendingPathComponent("thing"), withIntermediateDirectories: true)

        let result = try await compare()

        XCTAssertEqual(result.left["thing"], .differs)
        XCTAssertEqual(result.right["thing"], .differs)
    }

    func testIdenticalFolders() async throws {
        try write("a", "a.txt", in: left)
        try write("a", "a.txt", in: right)

        let result = try await compare()

        XCTAssertTrue(result.isIdentical)
    }

    func testCancelledComparisonThrows() async throws {
        try write("a", "a.txt", in: left)
        let flag = CancellationFlag()
        flag.cancel()

        do {
            _ = try await FolderComparisonService().compare(left, right, cancellation: flag)
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
    }

    // MARK: What Copy sends

    func testItemsToCopyAreNewerMissingAndDifferingFolders() throws {
        try write("x", "a.txt", in: left)
        try FileManager.default.createDirectory(at: left.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        let statuses: [String: ComparisonStatus] = [
            "new.txt": .onlyHere, "a.txt": .newerHere, "old.txt": .olderHere,
            "same.txt": .same, "sized.txt": .differs, "Folder": .differs,
        ]

        let items = FolderComparisonService.itemsToCopy(from: statuses, in: left) { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        XCTAssertEqual(items.map(\.lastPathComponent), ["a.txt", "Folder", "new.txt"])
    }

    func testSyncAnswerMergesFoldersAndOnlyReplacesWithNewer() {
        let now = Date()
        func conflict(_ name: String, dirIn: Bool, dirEx: Bool, inAge: Double, exAge: Double) -> FileConflictItem {
            FileConflictItem(
                source: URL(fileURLWithPath: "/l/\(name)"), existing: URL(fileURLWithPath: "/r/\(name)"),
                incoming: .init(isDirectory: dirIn, modified: now.addingTimeInterval(-inAge)),
                current: .init(isDirectory: dirEx, modified: now.addingTimeInterval(-exAge))
            )
        }
        let request = FileConflictRequest(conflicts: [
            conflict("folder", dirIn: true, dirEx: true, inAge: 100, exAge: 0),
            conflict("newer.txt", dirIn: false, dirEx: false, inAge: 0, exAge: 100),
            conflict("older.txt", dirIn: false, dirEx: false, inAge: 100, exAge: 0),
            conflict("kind", dirIn: false, dirEx: true, inAge: 0, exAge: 100),
        ], itemCount: 4, destination: URL(fileURLWithPath: "/r"), isMove: false)

        XCTAssertEqual(FolderComparisonService.syncAnswer(for: request), .resolve([
            URL(fileURLWithPath: "/l/folder"): .merge,
            URL(fileURLWithPath: "/l/newer.txt"): .replace,
            URL(fileURLWithPath: "/l/older.txt"): .skip,
            URL(fileURLWithPath: "/l/kind"): .skip,
        ]))
    }

    // MARK: Copy to Right, end to end

    func testCopyToRightBringsRightUpToDateWithoutLosingAnything() async throws {
        try write("new", "edited.txt", in: left, minutes: 10)
        try write("old", "edited.txt", in: right)
        try write("left wins? no", "rightNewer.txt", in: left)
        try write("keep me", "rightNewer.txt", in: right, minutes: 10)
        try write("x", "leftOnly.txt", in: left)
        try write("r", "rightOnly.txt", in: right)
        try write("deep new", "Folder/deep.txt", in: left, minutes: 10)
        try write("deep old", "Folder/deep.txt", in: right)
        try write("mine", "Folder/rightOnly.txt", in: right)
        try write("add", "Folder/sub/add.txt", in: left)

        let comparison = try await compare()
        let items = FolderComparisonService.itemsToCopy(from: comparison.left, in: left) { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        try await service.copyItems(items, to: right) { FolderComparisonService.syncAnswer(for: $0) }

        func read(_ path: String) throws -> String { try String(contentsOf: right.appendingPathComponent(path), encoding: .utf8) }
        XCTAssertEqual(try read("edited.txt"), "new")
        XCTAssertEqual(try read("rightNewer.txt"), "keep me", "nothing newer on the right is overwritten")
        XCTAssertEqual(try read("leftOnly.txt"), "x")
        XCTAssertEqual(try read("rightOnly.txt"), "r", "nothing on the right is deleted")
        XCTAssertEqual(try read("Folder/deep.txt"), "deep new")
        XCTAssertEqual(try read("Folder/rightOnly.txt"), "mine")
        XCTAssertEqual(try read("Folder/sub/add.txt"), "add")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fakeTrash.path).count, 2, "the two replaced files went to the Trash")

        let after = try await compare()
        XCTAssertTrue(after.left.values.allSatisfy { $0 == .same || $0 == .olderHere }, "nothing on the left is ahead any more: \(after.left)")
        XCTAssertEqual(after.left["edited.txt"], .same, "copies keep their dates, so a synced file reads as the same")
        XCTAssertEqual(after.left["Folder"], .olderHere, "the right's extra file inside makes it the side that's ahead")
    }

    // MARK: Panes

    @MainActor
    private func pane(at url: URL) async -> FileListViewModel {
        let viewModel = FileListViewModel(
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        )
        await viewModel.navigate(to: url).value
        return viewModel
    }

    @MainActor
    func testComparisonMarksBothPanesFiltersAndEndsWhenAPaneMoves() async throws {
        try write("same", "same.txt", in: left)
        try write("same", "same.txt", in: right)
        try write("x", "leftOnly.txt", in: left)
        let leftPane = await pane(at: left)
        let rightPane = await pane(at: right)
        let comparison = try XCTUnwrap(PaneComparison(left: leftPane, right: rightPane))
        var ended = false
        comparison.onEnd = { ended = true }

        comparison.start()
        while comparison.isComparing { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(leftPane.comparisonStatuses, ["same.txt": .same, "leftOnly.txt": .onlyHere])
        XCTAssertEqual(rightPane.comparisonStatuses, ["same.txt": .same])
        comparison.showsOnlyDifferences = true
        XCTAssertEqual(leftPane.items.map(\.name), ["leftOnly.txt"])
        XCTAssertEqual(rightPane.items.map(\.name), [])
        comparison.planSync(toRight: true)
        XCTAssertEqual(comparison.pendingSync?.items.map(\.lastPathComponent), ["leftOnly.txt"])

        await rightPane.navigate(to: tempDirectory).value

        XCTAssertTrue(ended)
        XCTAssertNil(leftPane.comparisonStatuses)
        XCTAssertNil(leftPane.comparisonFilter)
        XCTAssertEqual(Set(leftPane.items.map(\.name)), ["same.txt", "leftOnly.txt"], "the filter is gone")
    }
}
