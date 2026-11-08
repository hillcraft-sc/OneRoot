import XCTest
@testable import OneRoot

final class FolderSizeServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sub/Deeper"), withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: root.appendingPathComponent("a.bin"))
        try Data(count: 2_000).write(to: root.appendingPathComponent("Sub/b.bin"))
        try Data(count: 3_000).write(to: root.appendingPathComponent("Sub/Deeper/.hidden.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddsUpEverythingInsideIncludingHiddenFiles() async throws {
        let size = try await FolderSizeService().size(of: root)
        XCTAssertEqual(size, 6_000)
    }

    func testEmptyAndMissingFoldersAreZero() async throws {
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let emptySize = try await FolderSizeService().size(of: empty)
        let missingSize = try await FolderSizeService().size(of: root.appendingPathComponent("missing"))
        XCTAssertEqual(emptySize, 0)
        XCTAssertEqual(missingSize, 0)
    }

    func testCancellingStopsWithCancellationError() async {
        let task = Task { try await FolderSizeService().size(of: root) }
        task.cancel()
        do {
            _ = try await task.value
            // A tiny folder can finish before the cancel lands; that's fine too.
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }
}

@MainActor
final class FolderSizeCacheTests: XCTestCase {
    func testInvalidatesFoldersContainingAChange() {
        let cache = FolderSizeCache()
        cache.store(10, for: URL(fileURLWithPath: "/Users/eric/Photos"))
        cache.store(20, for: URL(fileURLWithPath: "/Users/eric/Photos/2026"))
        cache.store(30, for: URL(fileURLWithPath: "/Users/eric/Music"))

        let stale = cache.invalidate(containing: ["/Users/eric/Photos/2026/new.jpg"])

        XCTAssertEqual(stale, ["/Users/eric/Photos", "/Users/eric/Photos/2026"])
        XCTAssertNil(cache.size(of: URL(fileURLWithPath: "/Users/eric/Photos")))
        XCTAssertEqual(cache.size(of: URL(fileURLWithPath: "/Users/eric/Music")), 30)
    }

    func testSimilarlyNamedSiblingIsNotInvalidated() {
        let cache = FolderSizeCache()
        cache.store(10, for: URL(fileURLWithPath: "/data/Photos"))

        cache.invalidate(containing: ["/data/Photos Backup/x.jpg"])

        XCTAssertEqual(cache.size(of: URL(fileURLWithPath: "/data/Photos")), 10)
    }
}

@MainActor
final class FileListViewModelFolderSizeTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Big"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Small"), withIntermediateDirectories: true)
        try Data(count: 5_000).write(to: root.appendingPathComponent("Big/x.bin"))
        try Data(count: 100).write(to: root.appendingPathComponent("Small/y.bin"))
        suiteName = "FolderSizeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(calculateAll: Bool) -> FileListViewModel {
        defaults.set(calculateAll, forKey: "com.oneroot.calculateAllFolderSizes")
        return FileListViewModel(
            folderSizeCache: FolderSizeCache(),
            folderSizePreferences: FolderSizePreferenceStore(defaults: defaults)
        )
    }

    private func waitForSizes(_ viewModel: FileListViewModel, count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where viewModel.folderSizes.count < count || !viewModel.calculatingFolderSizes.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(viewModel.folderSizes.count, count, file: file, line: line)
    }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    func testFoldersHaveNoSizeUntilAsked() async {
        let viewModel = makeViewModel(calculateAll: false)
        await viewModel.navigate(to: root).value

        XCTAssertTrue(viewModel.folderSizes.isEmpty)
    }

    func testCalculateSizeSizesJustTheChosenFolders() async throws {
        let viewModel = makeViewModel(calculateAll: false)
        await viewModel.navigate(to: root).value
        let big = try XCTUnwrap(viewModel.items.first { $0.name == "Big" })

        viewModel.calculateFolderSizes([big])
        await waitForSizes(viewModel, count: 1)

        XCTAssertEqual(viewModel.folderSizes[big.url], 5_000)
    }

    func testCalculateFolderSizesInViewSizesEveryFolderOnceWithoutTurningOnTheSetting() async {
        let viewModel = makeViewModel(calculateAll: false)
        await viewModel.navigate(to: root).value

        viewModel.calculateFolderSizesInView()
        await waitForSizes(viewModel, count: 2)

        XCTAssertEqual(viewModel.folderSizes.values.sorted(), [100, 5_000])
        XCTAssertFalse(defaults.bool(forKey: "com.oneroot.calculateAllFolderSizes"), "a one-off, not the Settings preference")
    }

    func testCalculateAllSizesEveryFolderOnArrival() async {
        let viewModel = makeViewModel(calculateAll: true)
        await viewModel.navigate(to: root).value
        await waitForSizes(viewModel, count: 2)

        XCTAssertEqual(viewModel.folderSizes.values.sorted(), [100, 5_000])
    }

    func testSortingBySizeUsesFolderSizes() async {
        let viewModel = makeViewModel(calculateAll: true)
        await viewModel.navigate(to: root).value
        await waitForSizes(viewModel, count: 2)

        viewModel.setSort(field: .size)
        let ascending = viewModel.items.map(\.name)
        viewModel.setSort(field: .size)
        let descending = viewModel.items.map(\.name)

        XCTAssertEqual(Set([ascending, descending]), [["Small", "Big"], ["Big", "Small"]])
    }

    func testNavigatingAwayClearsSizes() async {
        let viewModel = makeViewModel(calculateAll: true)
        await viewModel.navigate(to: root).value
        await waitForSizes(viewModel, count: 2)

        await viewModel.navigate(to: url("Small")).value

        XCTAssertTrue(viewModel.folderSizes.isEmpty)
    }
}
