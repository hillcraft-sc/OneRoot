import XCTest
@testable import OneRoot

final class TrashOriginServiceTests: XCTestCase {
    private func makeService() -> TrashOriginService {
        TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testOriginalLocationWithNoRecordReturnsNil() {
        let service = makeService()

        XCTAssertNil(service.originalLocation(forTrashedURL: URL(fileURLWithPath: "/Users/test/.Trash/foo.txt")))
    }

    func testRecordOriginThenLookUp() {
        let service = makeService()
        let trashedURL = URL(fileURLWithPath: "/Users/test/.Trash/foo.txt")
        let originalURL = URL(fileURLWithPath: "/Users/test/Documents/foo.txt")

        service.recordOrigin(trashedURL: trashedURL, originalURL: originalURL)

        XCTAssertEqual(service.originalLocation(forTrashedURL: trashedURL), originalURL)
    }

    func testRemoveRecordClearsIt() {
        let service = makeService()
        let trashedURL = URL(fileURLWithPath: "/Users/test/.Trash/foo.txt")
        service.recordOrigin(trashedURL: trashedURL, originalURL: URL(fileURLWithPath: "/Users/test/Documents/foo.txt"))

        service.removeRecord(forTrashedURL: trashedURL)

        XCTAssertNil(service.originalLocation(forTrashedURL: trashedURL))
    }

    func testRecordsPersistAcrossInstances() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let trashedURL = URL(fileURLWithPath: "/Users/test/.Trash/foo.txt")
        let originalURL = URL(fileURLWithPath: "/Users/test/Documents/foo.txt")
        TrashOriginService(defaults: defaults).recordOrigin(trashedURL: trashedURL, originalURL: originalURL)

        let secondInstance = TrashOriginService(defaults: defaults)

        XCTAssertEqual(secondInstance.originalLocation(forTrashedURL: trashedURL), originalURL)
    }
}
