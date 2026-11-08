import XCTest
@testable import OneRoot

/// #72: the large-folder performance check run before each release
/// (`Scripts/benchmark.sh`, also run by `Scripts/release.sh`). Skipped in
/// normal test runs — it builds folders with tens of thousands of files.
/// Each step is timed against a generous budget, so a real regression
/// fails while a busy machine doesn't; the timings are written to
/// `ONEROOT_BENCHMARK_OUT` for the history file.
@MainActor
final class LargeFolderBenchmarkTests: XCTestCase {
    private var root: URL!
    private var results: [(name: String, seconds: Double, budget: Double)] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ONEROOT_BENCHMARK"] == "1", "set ONEROOT_BENCHMARK=1 (Scripts/benchmark.sh)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OneRootBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeFiles(_ count: Int, in folder: URL, prefix: String = "file") throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<count {
            let url = folder.appendingPathComponent("\(prefix)_\(index).txt")
            FileManager.default.createFile(atPath: url.path, contents: Data("\(index % 97)-\(String(repeating: "x", count: index % 300))".utf8))
        }
    }

    private func time(_ name: String, budget: Double, _ work: () async throws -> Void) async rethrows {
        let start = Date()
        try await work()
        let seconds = Date().timeIntervalSince(start)
        results.append((name, seconds, budget))
        print(String(format: "BENCH %-34@ %7.3fs  (budget %.1fs)", name as NSString, seconds, budget))
        XCTAssertLessThan(seconds, budget, "\(name) took \(seconds)s")
    }

    /// The defaults, not the developer's own settings (which the test host
    /// shares with the app).
    private var service: FileSystemService {
        var service = FileSystemService()
        service.usesSpotlightLastOpened = { false }
        return service
    }

    private func makeViewModel() -> FileListViewModel {
        FileListViewModel(
            fileSystemService: service,
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        )
    }

    func testLargeFolders() async throws {
        let big = root.appendingPathComponent("50k", isDirectory: true)
        try makeFiles(50_000, in: big)
        let tree = root.appendingPathComponent("tree", isDirectory: true)
        for folder in 0..<200 {
            try makeFiles(100, in: tree.appendingPathComponent("folder \(folder)"), prefix: "f\(folder)")
        }
        let treeCopy = root.appendingPathComponent("tree copy", isDirectory: true)
        try FileManager.default.copyItem(at: tree, to: treeCopy)

        let service = self.service
        try await time("List 50,000 files", budget: 5) {
            let nodes = try await service.listDirectory(big)
            XCTAssertEqual(nodes.count, 50_000)
        }
        var spotlight = FileSystemService()
        spotlight.usesSpotlightLastOpened = { true }
        try await time("List 50,000 with Spotlight dates", budget: 15) {
            let nodes = try await spotlight.listDirectory(big, wantsLastOpenedDates: true)
            XCTAssertEqual(nodes.count, 50_000)
        }

        let viewModel = makeViewModel()
        await time("Open a 50,000-file folder", budget: 6) {
            await viewModel.navigate(to: big).value
            XCTAssertEqual(viewModel.items.count, 50_000)
        }
        await time("Sort 50,000 by size", budget: 2) {
            viewModel.setSort(field: .size)
            XCTAssertEqual(viewModel.items.count, 50_000)
        }
        await time("Filter 50,000 by name", budget: 2) {
            viewModel.searchText = "file_4999"
            XCTAssertFalse(viewModel.items.isEmpty)
        }
        viewModel.clearFilter()

        let flat = makeViewModel()
        await flat.navigate(to: tree).value
        await time("Flat view of 20,000 files", budget: 4) {
            await flat.setShowsAllFilesInSubfolders(true)?.value
            XCTAssertEqual(flat.items.count, 20_000)
        }

        try await time("Compare two 20,000-file trees", budget: 4) {
            let result = try await FolderComparisonService().compare(tree, treeCopy, cancellation: CancellationFlag())
            XCTAssertTrue(result.isIdentical)
        }

        try await time("Find duplicates in 40,000 files", budget: 8) {
            _ = try await DuplicateFinder().find(in: [tree, treeCopy], includeHidden: false, cancellation: CancellationFlag())
        }

        if let out = ProcessInfo.processInfo.environment["ONEROOT_BENCHMARK_OUT"] {
            let json = results.map { ["name": $0.name, "seconds": $0.seconds, "budget": $0.budget] as [String: Any] }
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: out))
        }
    }
}
