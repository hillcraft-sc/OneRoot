import XCTest
@testable import OneRoot

/// A fixed Spotlight answer, so Recents can be tested without the index.
private struct FakeIndex: RecentItemsQuerying {
    var used: [(String, Date)] = []
    func recentlyUsed(withinDays days: Int, under roots: [URL]) -> [(path: String, lastUsed: Date)] {
        used.map { ($0.0, $0.1) }
    }
}

/// Recents and Shared for a view model test, without Spotlight or iCloud.
private struct FakeListing: VirtualListing {
    let nodes: [FileNode]
    func items(for location: VirtualLocation) async throws -> [FileNode] { nodes }
}

final class VirtualLocationTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents/Project"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testURLsRoundTripAndAreNeverFileURLs() {
        for location in VirtualLocation.allCases {
            XCTAssertFalse(location.url.isFileURL)
            XCTAssertEqual(VirtualLocation(url: location.url), location)
        }
        XCTAssertNil(VirtualLocation(url: URL(fileURLWithPath: "/recents")))
        XCTAssertEqual(BreadcrumbBuilder.segments(for: VirtualLocation.recents.url).map(\.name), ["Recents"])
        #if !SWIFT_PACKAGE // TabTitle is a SwiftUI view: Mac app only
        XCTAssertEqual(TabTitle.title(for: VirtualLocation.shared.url), "Shared")
        #endif
    }

    func testRecentsUsesSpotlightsDateKeepsICloudAndLeavesOutLibraryHiddenAndFolders() throws {
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        let doc = home.appendingPathComponent("Documents/report.pdf")
        let wishlist = iCloud.appendingPathComponent("Wishlist.csv")
        let cache = home.appendingPathComponent("Library/Caches/cache.db")
        let hidden = home.appendingPathComponent(".config")
        for url in [doc, wishlist, cache, hidden] { try "x".write(to: url, atomically: true, encoding: .utf8) }
        let folder = home.appendingPathComponent("Documents/Project")
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let index = FakeIndex(used: [(doc.path, old), (wishlist.path, new), (cache.path, new), (hidden.path, new), (folder.path, new)])
        let service = VirtualListingService(index: index, home: home, iCloudDrive: iCloud)

        let recents = try service.recents()

        XCTAssertEqual(recents.map(\.name), ["Wishlist.csv", "report.pdf"], "newest first by Spotlight's date")
        XCTAssertEqual(recents.map(\.lastOpenedDate), [new, old])
    }

    func testSharedIsEmptyWithoutICloudDrive() throws {
        let service = VirtualListingService(index: FakeIndex(), home: home, iCloudDrive: home.appendingPathComponent("NoSuchDrive"))
        XCTAssertEqual(try service.shared().count, 0)
    }
}

@MainActor
final class VirtualLocationViewModelTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeViewModel(_ nodes: [FileNode]) -> FileListViewModel {
        let history = NavigationHistoryStore(service: NavigationHistoryService(defaults: .isolatedForTests()))
        // Its own column settings: the app's saved ones (shared with a
        // OneRoot in daily use) could already show Where.
        let columns = ColumnPreferencesStore(service: ColumnPreferencesService(defaults: .isolatedForTests()))
        return FileListViewModel(columnPreferences: columns, navigationHistory: history, virtualListing: FakeListing(nodes: nodes))
    }

    func testRecentsReplacesTheFolderAndBackReturns() async throws {
        let recent = FileNode(url: URL(fileURLWithPath: "/tmp/elsewhere/a.txt"), name: "a.txt", isDirectory: false, size: 1, modificationDate: nil, kind: nil)
        let viewModel = makeViewModel([recent])
        await viewModel.navigate(to: folder).value
        viewModel.setSort(field: .size)

        await viewModel.navigate(to: VirtualLocation.recents.url).value

        XCTAssertNil(viewModel.currentDirectory)
        XCTAssertEqual(viewModel.virtualLocation, .recents)
        XCTAssertEqual(viewModel.currentLocationURL, VirtualLocation.recents.url)
        XCTAssertEqual(viewModel.items.map(\.name), ["a.txt"])
        XCTAssertFalse(viewModel.canGoUp)
        XCTAssertEqual(viewModel.sortField, .dateLastOpened, "Recents sorts by when things were opened")
        XCTAssertEqual(Array(viewModel.displayedColumns.prefix(2)), [.name, .location])

        await viewModel.goBack()?.value

        XCTAssertEqual(viewModel.currentDirectory, folder)
        XCTAssertNil(viewModel.virtualLocation)
        XCTAssertEqual(viewModel.sortField, .size, "the folder's sort comes back")
        XCTAssertFalse(viewModel.displayedColumns.contains(.location))
        XCTAssertTrue(viewModel.canGoForward)

        await viewModel.goForward()?.value
        XCTAssertEqual(viewModel.virtualLocation, .recents)
    }

    func testRecentsClosesTheHierarchyAndLeavingReopensIt() async {
        let windowViewModel = WindowViewModel(navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: .isolatedForTests())))
        windowViewModel.layout.set(\.showsHierarchy, true)

        windowViewModel.setShowingList(true)
        XCTAssertFalse(windowViewModel.layout.layout.showsHierarchy)
        windowViewModel.setShowingList(false)
        XCTAssertTrue(windowViewModel.layout.layout.showsHierarchy)

        // Closed by hand beforehand: it stays closed after.
        windowViewModel.layout.set(\.showsHierarchy, false)
        windowViewModel.setShowingList(true)
        windowViewModel.setShowingList(false)
        XCTAssertFalse(windowViewModel.layout.layout.showsHierarchy)
    }

    func testTheSessionSavesAndRestoresRecents() {
        let windowViewModel = WindowViewModel(navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: .isolatedForTests())))
        windowViewModel.activeTab?.fileListViewModel.navigate(to: VirtualLocation.recents.url)
        let saved = windowViewModel.savedState(frame: nil)
        XCTAssertEqual(saved.tabs.first?.primary.path, VirtualLocation.recents.url.absoluteString)
    }
}

final class LastOpenedDateSourceTests: XCTestCase {
    func testListingUsesSpotlightsDateOnlyWhenChosen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let opened = folder.appendingPathComponent("opened.txt"), never = folder.appendingPathComponent("never.txt")
        for url in [opened, never] { try "x".write(to: url, atomically: true, encoding: .utf8) }
        let spotlightDate = Date(timeIntervalSince1970: 1_234_567)
        let lookup: @Sendable (String) -> Date? = { $0.hasSuffix("opened.txt") ? spotlightDate : nil }

        var off = FileSystemService()
        off.usesSpotlightLastOpened = { false }
        off.spotlightLastUsedDate = lookup
        let byAccess = try await off.listDirectory(folder)
        XCTAssertNotNil(byAccess.first { $0.name == "never.txt" }?.lastOpenedDate, "off: the access time, which every file has")

        var on = off
        on.usesSpotlightLastOpened = { true }
        let bySpotlight = try await on.listDirectory(folder, wantsLastOpenedDates: true)
        XCTAssertEqual(bySpotlight.first { $0.name == "opened.txt" }?.lastOpenedDate, spotlightDate)
        XCTAssertNil(bySpotlight.first { $0.name == "never.txt" }?.lastOpenedDate, "on: never opened shows no date, as in Finder")

        // A listing that doesn't show the column never asks Spotlight (#72).
        on.spotlightLastUsedDate = { _ in XCTFail("Spotlight asked for a listing that doesn't need it"); return nil }
        _ = try await on.listDirectory(folder)
    }
}

final class FileDateFormatTests: XCTestCase {
    func testTodayAndYesterdayOnlyWhenChosen() {
        let defaults = UserDefaults.isolatedForTests()
        let now = Date()
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        XCTAssertFalse(FileDateFormat.string(from: now, defaults: defaults).contains("Today"))

        defaults.set(true, forKey: FileDateFormat.usesRelativeDatesKey)
        XCTAssertTrue(FileDateFormat.string(from: now, defaults: defaults).contains("Today"))
        // Older dates read the same either way.
        defaults.set(false, forKey: FileDateFormat.usesRelativeDatesKey)
        let plain = FileDateFormat.string(from: lastWeek, defaults: defaults)
        defaults.set(true, forKey: FileDateFormat.usesRelativeDatesKey)
        XCTAssertEqual(FileDateFormat.string(from: lastWeek, defaults: defaults), plain)
    }
}
