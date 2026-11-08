import XCTest
@testable import OneRoot

final class BatchRenameServiceTests: XCTestCase {
    private let service = BatchRenameService()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func urls(_ names: String...) -> [URL] {
        names.map { folder.appendingPathComponent($0) }
    }

    @discardableResult
    private func make(_ names: String...) throws -> [URL] {
        try names.map { name in
            let url = folder.appendingPathComponent(name)
            try name.write(to: url, atomically: true, encoding: .utf8) // contents = original name, to track items
            return url
        }
    }

    private func contents(of name: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: Naming

    func testReplaceKeepsTheExtensionByDefault() throws {
        let names = try service.newNames(for: urls("IMG_001.jpg", "IMG_002.jpg"), rule: .replace(find: "IMG_", with: "Trip ", caseSensitive: false, regex: false))
        XCTAssertEqual(names, ["Trip 001.jpg", "Trip 002.jpg"])
    }

    func testReplaceCanIncludeTheExtension() throws {
        let names = try service.newNames(for: urls("a.jpeg"), rule: .replace(find: "jpeg", with: "jpg", caseSensitive: false, regex: false), includeExtension: true)
        XCTAssertEqual(names, ["a.jpg"])
    }

    func testReplaceCaseSensitivity() throws {
        let insensitive = try service.newNames(for: urls("Draft.txt"), rule: .replace(find: "draft", with: "Final", caseSensitive: false, regex: false))
        let sensitive = try service.newNames(for: urls("Draft.txt"), rule: .replace(find: "draft", with: "Final", caseSensitive: true, regex: false))
        XCTAssertEqual(insensitive, ["Final.txt"])
        XCTAssertEqual(sensitive, ["Draft.txt"])
    }

    func testRegexReplaceWithCaptureGroups() throws {
        let names = try service.newNames(for: urls("01 - Intro.mp3"), rule: .replace(find: #"^(\d+) - (.+)$"#, with: "$2 ($1)", caseSensitive: false, regex: true))
        XCTAssertEqual(names, ["Intro (01).mp3"])
    }

    func testInvalidRegexThrows() {
        XCTAssertThrowsError(try service.newNames(for: urls("a.txt"), rule: .replace(find: "(", with: "", caseSensitive: false, regex: true)))
    }

    func testAddBeforeAndAfter() throws {
        XCTAssertEqual(try service.newNames(for: urls("report.pdf"), rule: .add(text: "2026 ", position: .before)), ["2026 report.pdf"])
        XCTAssertEqual(try service.newNames(for: urls("report.pdf"), rule: .add(text: " v2", position: .after)), ["report v2.pdf"])
    }

    func testFormatCountsAndPads() throws {
        let names = try service.newNames(for: urls("x.jpg", "y.jpg", "z.png"), rule: .format(base: "Vacation", counterPosition: .after, start: 9, digits: 3))
        XCTAssertEqual(names, ["Vacation 009.jpg", "Vacation 010.jpg", "Vacation 011.png"])
    }

    func testFormatNumberFirstAndNumbersOnly() throws {
        XCTAssertEqual(try service.newNames(for: urls("x.jpg"), rule: .format(base: "Shot", counterPosition: .before, start: 1, digits: 2)), ["01 Shot.jpg"])
        XCTAssertEqual(try service.newNames(for: urls("x.jpg"), rule: .format(base: "", counterPosition: .after, start: 1, digits: 1)), ["1.jpg"])
    }

    func testChangeCase() throws {
        XCTAssertEqual(try service.newNames(for: urls("My File.TXT"), rule: .changeCase(.lowercase)), ["my file.TXT"])
        XCTAssertEqual(try service.newNames(for: urls("my file.txt"), rule: .changeCase(.uppercase)), ["MY FILE.txt"])
        XCTAssertEqual(try service.newNames(for: urls("my file.txt"), rule: .changeCase(.titleCase)), ["My File.txt"])
    }

    func testDotFilesAreAllNameNoExtension() throws {
        XCTAssertEqual(try service.newNames(for: urls(".gitignore"), rule: .add(text: ".bak", position: .after)), [".gitignore.bak"])
    }

    // MARK: Problems

    func testDuplicatesWithinTheBatchAreFlagged() {
        let problems = service.problems(for: urls("a.txt", "b.txt"), newNames: ["same.txt", "Same.txt"])
        XCTAssertEqual(problems, [0: .duplicateInBatch, 1: .duplicateInBatch])
    }

    func testClashWithAnotherFileInTheFolderIsFlagged() throws {
        try make("a.txt", "taken.txt")
        let problems = service.problems(for: urls("a.txt"), newNames: ["taken.txt"])
        XCTAssertEqual(problems, [0: .existsInFolder])
    }

    func testANameFreedByTheBatchIsNotAClash() throws {
        try make("a.txt", "b.txt")
        let problems = service.problems(for: urls("a.txt", "b.txt"), newNames: ["b.txt", "a.txt"]) // a swap
        XCTAssertEqual(problems, [:])
    }

    func testCaseOnlyChangeIsNotAClashWithItself() throws {
        try make("photo.jpg")
        XCTAssertEqual(service.problems(for: urls("photo.jpg"), newNames: ["Photo.jpg"]), [:])
    }

    func testInvalidNamesAreFlagged() {
        let problems = service.problems(for: urls("a.txt", "b.txt", "c.txt"), newNames: [" ", "x/y.txt", ".hidden.txt"])
        XCTAssertEqual(problems, [0: .empty, 1: .invalidCharacter, 2: .startsWithDot])
    }

    // MARK: Applying

    func testApplyRenamesAndReturnsUndoableChanges() async throws {
        let originals = try make("a.txt", "b.txt")

        let changes = try await service.apply(urls: originals, newNames: ["one.txt", "two.txt"])

        XCTAssertEqual(try contents(of: "one.txt"), "a.txt")
        XCTAssertEqual(try contents(of: "two.txt"), "b.txt")
        XCTAssertEqual(changes, [
            .moved(from: originals[0], to: folder.appendingPathComponent("one.txt")),
            .moved(from: originals[1], to: folder.appendingPathComponent("two.txt")),
        ])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["one.txt", "two.txt"], "no temporary files left")
    }

    func testApplyHandlesASwap() async throws {
        let originals = try make("a.txt", "b.txt")

        _ = try await service.apply(urls: originals, newNames: ["b.txt", "a.txt"])

        XCTAssertEqual(try contents(of: "b.txt"), "a.txt")
        XCTAssertEqual(try contents(of: "a.txt"), "b.txt")
    }

    func testApplyHandlesACaseOnlyChange() async throws {
        let originals = try make("photo.jpg")

        _ = try await service.apply(urls: originals, newNames: ["Photo.jpg"])

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Photo.jpg"])
    }

    func testApplySkipsUnchangedItems() async throws {
        let originals = try make("keep.txt", "change.txt")

        let changes = try await service.apply(urls: originals, newNames: ["keep.txt", "changed.txt"])

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(try contents(of: "keep.txt"), "keep.txt")
    }

    func testAFailurePutsEverythingBack() async throws {
        let originals = try make("a.txt", "b.txt")
        // Second item's target folder doesn't exist, so its final rename fails.
        do {
            _ = try await service.apply(urls: originals, newNames: ["one.txt", "missing-folder/two.txt"])
            XCTFail("expected a failure")
        } catch {}

        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["a.txt", "b.txt"], "all or nothing")
        XCTAssertEqual(try contents(of: "a.txt"), "a.txt")
    }
}
