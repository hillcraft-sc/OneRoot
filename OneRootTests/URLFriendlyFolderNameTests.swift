import XCTest
@testable import OneRoot

final class URLFriendlyFolderNameTests: XCTestCase {
    func testICloudDriveContainerBecomesICloudDrive() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs")

        XCTAssertEqual(url.friendlyFolderName, "iCloud Drive")
    }

    func testThirdPartyCloudStorageProviderIsTrimmedToItsName() {
        let url = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Nextcloud-a8f499f1@nextcloud.example.com")

        XCTAssertEqual(url.friendlyFolderName, "Nextcloud")
    }

    func testCloudStorageProviderWithoutAHyphenIsShownAsIs() {
        let url = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/SomeProvider")

        XCTAssertEqual(url.friendlyFolderName, "SomeProvider")
    }

    /// The regression this guards against: naively trimming at the first
    /// hyphen for *any* folder would mangle ordinary folder names outside
    /// CloudStorage/Mobile Documents.
    func testOrdinaryFolderWithAHyphenIsNotTruncated() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/Project-Files")

        XCTAssertEqual(url.friendlyFolderName, "Project-Files")
    }

    func testNameMatchingComCloudDocsOutsideMobileDocumentsIsNotRenamed() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/com~apple~CloudDocs")

        XCTAssertEqual(url.friendlyFolderName, "com~apple~CloudDocs")
    }
}
