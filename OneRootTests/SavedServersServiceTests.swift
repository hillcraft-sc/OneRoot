import XCTest
@testable import OneRoot

final class SavedServersServiceTests: XCTestCase {
    private func makeService() -> SavedServersService {
        SavedServersService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testLoadWithNoSavedDataReturnsEmpty() {
        let service = makeService()

        XCTAssertTrue(service.load().isEmpty)
    }

    func testAddThenLoadRoundTrips() {
        let service = makeService()
        let server = SavedServer(name: "Media Server", url: URL(string: "smb://media.local/share")!)

        let result = service.add(server)

        XCTAssertEqual(result, [server])
        XCTAssertEqual(service.load(), [server])
    }

    func testAddIgnoresDuplicateURL() {
        let service = makeService()
        let url = URL(string: "smb://media.local/share")!
        service.add(SavedServer(name: "First Name", url: url))

        let result = service.add(SavedServer(name: "Second Name", url: url))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "First Name")
    }

    func testRemoveDeletesMatchingServer() {
        let service = makeService()
        let server = SavedServer(name: "Media Server", url: URL(string: "smb://media.local/share")!)
        service.add(server)

        let result = service.remove(id: server.id)

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(service.load().isEmpty)
    }

    func testRemoveWithUnknownIdLeavesListUnchanged() {
        let service = makeService()
        let server = SavedServer(name: "Media Server", url: URL(string: "smb://media.local/share")!)
        service.add(server)

        let result = service.remove(id: UUID())

        XCTAssertEqual(result, [server])
    }
}
