import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class NetworkPlacesTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text)! }

    func testTitlesNameTheShareAndHost() {
        XCTAssertEqual(NetworkPlaces.title(for: url("smb://192.168.1.20/timemachine")), "timemachine on 192.168.1.20")
        XCTAssertEqual(NetworkPlaces.title(for: url("smb://nas.local/")), "nas.local")
    }

    func testKeyIgnoresSlashCaseAndDefaultPort() {
        XCTAssertEqual(NetworkPlaces.key(url("smb://NAS.local:445/")), NetworkPlaces.key(url("smb://nas.local")))
        XCTAssertNotEqual(NetworkPlaces.key(url("smb://nas.local/a")), NetworkPlaces.key(url("smb://nas.local/b")))
        XCTAssertNotEqual(NetworkPlaces.key(url("sftp://h:2222/")), NetworkPlaces.key(url("sftp://h/")))
    }

    func testFavoritesComeBeforeAnnouncedServers() {
        let favorite = SavedServer(name: "Office", url: url("smb://office/share"))
        let places = NetworkPlaces.combine(favorites: [favorite], found: [NetworkServer(name: "printer", address: "smb://printer/")], aliases: [:])
        XCTAssertEqual(places.map(\.kind), [.favorite, .found])
        XCTAssertEqual(places[0].favoriteID, favorite.id)
        XCTAssertEqual(places[0].title, "Office")
    }

    func testAFavoriteNamedAfterItsHostShowsTheShare() {
        let favorite = SavedServer(name: "192.168.1.20", url: url("smb://192.168.1.20/timemachine"))
        XCTAssertEqual(NetworkPlaces.combine(favorites: [favorite], found: [], aliases: [:])[0].title, "timemachine on 192.168.1.20")
    }

    func testAnAnnouncedServerYouHaveAsAFavoriteUnderItsIPIsHidden() {
        let places = NetworkPlaces.combine(
            favorites: [SavedServer(name: "192.168.1.20", url: url("smb://192.168.1.20/timemachine"))],
            found: [NetworkServer(name: "nas", address: "smb://nas.local:445/"),
                    NetworkServer(name: "other", address: "smb://other.local/")],
            aliases: ["192.168.1.20": ["192.168.1.20"], "nas.local": ["nas.local", "192.168.1.20"], "other.local": ["other.local", "192.168.1.99"]])
        XCTAssertEqual(places.map(\.address), ["smb://192.168.1.20/timemachine", "smb://other.local/"])
    }
}
