import XCTest
@testable import OneRoot

/// Find Duplicates (#67).
final class DuplicateFinderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ data: Data, _ path: String, minutesAgo: Double = 0) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
        return url
    }

    private func find(_ roots: [URL]? = nil) async throws -> [DuplicateGroup] {
        try await DuplicateFinder().find(in: roots ?? [root], includeHidden: false, cancellation: CancellationFlag())
    }

    func testIdenticalFilesAcrossSubfoldersAreGroupedOldestFirst() async throws {
        let photo = Data(repeating: 7, count: 10_000)
        try write(photo, "a/photo.jpg", minutesAgo: 5)
        try write(photo, "b/c/photo copy.jpg", minutesAgo: 60)
        try write(photo, "photo (2).jpg", minutesAgo: 1)
        try write(Data("unique".utf8), "other.txt")

        let groups = try await find()

        XCTAssertEqual(groups.count, 1)
        guard let first = groups.first else { return }
        XCTAssertEqual(first.files.map(\.url.lastPathComponent), ["photo copy.jpg", "photo.jpg", "photo (2).jpg"])
        XCTAssertEqual(first.size, 10_000)
        XCTAssertEqual(first.reclaimable, 20_000)
    }

    func testSameSizeOrSameStartIsntEnough() async throws {
        try write(Data(repeating: 1, count: 100), "a.bin")
        try write(Data(repeating: 2, count: 100), "b.bin")
        var long1 = Data(repeating: 3, count: 10_000)
        var long2 = long1
        long1[9_999] = 0
        long2[9_999] = 1
        try write(long1, "c.bin")
        try write(long2, "d.bin") // same first 4 KB, different end

        let groups = try await find()

        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyFilesHardLinksPackagesAndHiddenFilesAreLeftOut() async throws {
        try write(Data(), "empty1")
        try write(Data(), "empty2")
        let original = try write(Data(repeating: 9, count: 500), "linked.bin")
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("hardlink.bin"))
        let inside = Data(repeating: 4, count: 300)
        #if os(macOS) // Linux has no packages: Tool.app is a plain folder there
        try write(inside, "Tool.app/Contents/a.dat")
        try write(inside, "Other.app/Contents/a.dat")
        #endif
        try write(inside, ".hidden1")
        try write(inside, ".hidden2")

        let groups = try await find()

        XCTAssertTrue(groups.isEmpty, "\(groups.map { $0.files.map(\.url.lastPathComponent) })")
    }

    func testTwoRootsAreSearchedTogetherAndBiggestSavingsComeFirst() async throws {
        let small = Data(repeating: 5, count: 1_000)
        let big = Data(repeating: 6, count: 50_000)
        try write(small, "left/s.txt"); try write(small, "right/s.txt")
        try write(big, "left/b.bin"); try write(big, "right/b.bin")

        let groups = try await find([root.appendingPathComponent("left"), root.appendingPathComponent("right")])

        XCTAssertEqual(groups.map(\.size), [50_000, 1_000])
    }

    func testCancelled() async throws {
        try write(Data("x".utf8), "a")
        let flag = CancellationFlag()
        flag.cancel()
        do {
            _ = try await DuplicateFinder().find(in: [root], includeHidden: false, cancellation: flag)
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
    }

    // MARK: Marking

    @MainActor
    func testMarkingAlwaysKeepsOneOfEachSet() async throws {
        let data = Data(repeating: 8, count: 2_000)
        try write(data, "x/1.dat", minutesAgo: 30)
        try write(data, "x/2.dat", minutesAgo: 20)
        try write(data, "x/3.dat", minutesAgo: 10)
        let viewModel = DuplicatesViewModel()
        await viewModel.start([root]).value
        let group = try XCTUnwrap(viewModel.groups.first)

        viewModel.markAllButOne(keepingNewest: false)
        XCTAssertEqual(viewModel.marked, Set(group.files.dropFirst().map(\.url)), "the oldest stays")
        XCTAssertEqual(viewModel.markedSize, 4_000)
        XCTAssertFalse(viewModel.canMark(group.files[0], in: group), "the last unmarked copy can't be marked")
        viewModel.toggle(group.files[0], in: group)
        XCTAssertFalse(viewModel.isMarked(group.files[0]))

        viewModel.markAllButOne(keepingNewest: true)
        XCTAssertFalse(viewModel.isMarked(group.files[2]))
        XCTAssertNil(viewModel.trashMarked(confirm: { _ in false }), "declining the confirmation trashes nothing")
        XCTAssertEqual(viewModel.groups.first?.files.count, 3)
    }
}
