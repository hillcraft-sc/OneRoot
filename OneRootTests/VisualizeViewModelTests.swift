import XCTest
@testable import OneRoot

@MainActor
final class VisualizeViewModelTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        VisualizeViewModel.clearCache()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["a", "b"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(count: name == "a" ? 100 : 200).write(to: folder.appendingPathComponent("file.bin"))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testShowsTheFoldersReport() async {
        let viewModel = VisualizeViewModel()
        viewModel.show(root.appendingPathComponent("a"), delay: .zero)

        await waitUntil { viewModel.report?.isComplete == true }

        XCTAssertEqual(viewModel.report?.totalSize, 100)
        XCTAssertFalse(viewModel.isScanning)
    }

    func testAnotherFolderReplacesTheScanAndComingBackIsInstant() async {
        let viewModel = VisualizeViewModel()
        viewModel.show(root.appendingPathComponent("a"), delay: .zero)
        await waitUntil { viewModel.report?.isComplete == true }

        viewModel.show(root.appendingPathComponent("b"), delay: .zero)
        await waitUntil { viewModel.report?.totalSize == 200 && viewModel.report?.isComplete == true }
        XCTAssertEqual(viewModel.report?.root.lastPathComponent, "b")

        viewModel.show(root.appendingPathComponent("a"), delay: .zero)
        XCTAssertEqual(viewModel.report?.totalSize, 100, "cached — shown without a new scan")
        XCTAssertFalse(viewModel.isScanning)
    }

    func testAFolderThatIsGoneShowsAnError() async {
        let viewModel = VisualizeViewModel()
        viewModel.show(root.appendingPathComponent("missing"), delay: .zero)

        await waitUntil { viewModel.errorMessage != nil }

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isScanning)
    }
}
