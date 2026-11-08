import XCTest
@testable import OneRoot

final class PathResolverTests: XCTestCase {
    private let resolver = PathResolver()
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testResolvesExistingAbsoluteDirectory() {
        let result = resolver.resolve(tempDirectory.path)

        switch result {
        case .success(.local(let url)):
            XCTAssertEqual(url.standardizedFileURL.path, tempDirectory.standardizedFileURL.path)
        default:
            XCTFail("expected .success(.local), got \(result)")
        }
    }

    func testExpandsTilde() {
        let result = resolver.resolve("~")

        switch result {
        case .success(.local(let url)):
            XCTAssertEqual(url.standardizedFileURL.path, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
        default:
            XCTFail("expected .success(.local), got \(result)")
        }
    }

    func testMissingPathFails() {
        let result = resolver.resolve(tempDirectory.appendingPathComponent("nope").path)

        guard case .failure(.notFound) = result else {
            return XCTFail("expected .notFound")
        }
    }

    func testFilePathIsNotADirectory() throws {
        let fileURL = tempDirectory.appendingPathComponent("file.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = resolver.resolve(fileURL.path)

        guard case .failure(.notADirectory) = result else {
            return XCTFail("expected .notADirectory")
        }
    }

    func testNetworkShareIsRecognizedAsMountable() {
        let result = resolver.resolve("smb://fileserver/share")

        guard case .success(.networkShare(let url)) = result else {
            return XCTFail("expected .success(.networkShare), got \(result)")
        }
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.host, "fileserver")
    }

    func testNetworkAddressWithoutHostFails() {
        let result = resolver.resolve("smb://")

        guard case .failure(.invalidNetworkAddress) = result else {
            return XCTFail("expected .invalidNetworkAddress")
        }
    }

    func testUnsupportedFormatFails() {
        let result = resolver.resolve("relative/path")

        guard case .failure(.unsupportedFormat) = result else {
            return XCTFail("expected .unsupportedFormat")
        }
    }

    func testEmptyInputFails() {
        let result = resolver.resolve("   ")

        guard case .failure(.empty) = result else {
            return XCTFail("expected .empty")
        }
    }

    // MARK: splitForAutocomplete

    func testSplitForAutocompleteSeparatesDirectoryFromPrefix() {
        let result = resolver.splitForAutocomplete("/Users/eric/Doc")

        XCTAssertEqual(result?.directory.path, "/Users/eric")
        XCTAssertEqual(result?.prefix, "Doc")
    }

    func testSplitForAutocompleteWithTrailingSlashHasEmptyPrefix() {
        let result = resolver.splitForAutocomplete("/Users/eric/")

        XCTAssertEqual(result?.directory.path, "/Users/eric")
        XCTAssertEqual(result?.prefix, "")
    }

    func testSplitForAutocompleteExpandsTilde() {
        let result = resolver.splitForAutocomplete("~/Doc")

        XCTAssertEqual(result?.directory.path, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertEqual(result?.prefix, "Doc")
    }

    func testSplitForAutocompleteBareTildeIsHomeWithEmptyPrefix() {
        let result = resolver.splitForAutocomplete("~")

        XCTAssertEqual(result?.directory.path, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertEqual(result?.prefix, "")
    }

    func testSplitForAutocompleteAtRootLevel() {
        let result = resolver.splitForAutocomplete("/Us")

        XCTAssertEqual(result?.directory.path, "/")
        XCTAssertEqual(result?.prefix, "Us")
    }

    func testSplitForAutocompleteReturnsNilForNetworkAddress() {
        XCTAssertNil(resolver.splitForAutocomplete("smb://fileserver/share"))
    }

    func testSplitForAutocompleteReturnsNilForUnsupportedFormat() {
        XCTAssertNil(resolver.splitForAutocomplete("relative/path"))
    }
}
