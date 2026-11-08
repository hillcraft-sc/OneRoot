import XCTest
@testable import OneRoot

final class ColumnPreferencesServiceTests: XCTestCase {
    private func makeService() -> ColumnPreferencesService {
        ColumnPreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testLoadWithNoSavedDataReturnsDefaultVisible() {
        let service = makeService()

        XCTAssertEqual(service.load(), FileColumn.defaultVisible)
    }

    func testSaveThenLoadRoundTrips() {
        let service = makeService()
        let columns: [FileColumn] = [.name, .size, .tags]

        service.save(columns)

        XCTAssertEqual(service.load(), columns)
    }

    func testSaveOverwritesPreviousValue() {
        let service = makeService()
        service.save([.name, .kind])

        service.save([.name, .dateCreated])

        XCTAssertEqual(service.load(), [.name, .dateCreated])
    }
}
