import XCTest
@testable import OneRoot

final class FolderViewModeServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var service: FolderViewModeService!

    override func setUp() {
        suiteName = "FolderViewModeServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = FolderViewModeService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let photos = URL(fileURLWithPath: "/Users/eric/Pictures/Photos")
    private let documents = URL(fileURLWithPath: "/Users/eric/Documents")

    func testFoldersDefaultToList() {
        XCTAssertEqual(service.mode(for: photos), .list)
    }

    func testRemembersEachFolderSeparately() {
        service.setMode(.icons, for: photos)

        XCTAssertEqual(service.mode(for: photos), .icons)
        XCTAssertEqual(service.mode(for: documents), .list)
    }

    func testSpellingsOfTheSameFolderMatch() {
        service.setMode(.icons, for: URL(fileURLWithPath: "/Users/eric/Pictures/./Photos/"))

        XCTAssertEqual(service.mode(for: photos), .icons)
    }

    func testSettingBackToListForgetsTheFolder() {
        service.setMode(.icons, for: photos)
        service.setMode(.list, for: photos)

        XCTAssertEqual(service.mode(for: photos), .list)
        let stored = try? JSONSerialization.jsonObject(with: defaults.data(forKey: "com.oneroot.folderViewModes") ?? Data()) as? [Any]
        XCTAssertEqual(stored?.count, 0, "the default isn't stored")
    }

    func testOldestFoldersAreDroppedPastTheCap() {
        let first = URL(fileURLWithPath: "/folder-0")
        for index in 0...FolderViewModeService.maxEntries {
            service.setMode(.icons, for: URL(fileURLWithPath: "/folder-\(index)"))
        }

        XCTAssertEqual(service.mode(for: first), .list, "the oldest entry fell off")
        XCTAssertEqual(service.mode(for: URL(fileURLWithPath: "/folder-\(FolderViewModeService.maxEntries)")), .icons)
    }
}
