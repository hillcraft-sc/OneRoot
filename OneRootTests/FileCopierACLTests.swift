#if os(macOS) // tests the macOS copy engine
import XCTest
@testable import OneRoot

/// Copies of folders marked "everyone deny delete" (as macOS marks
/// Desktop, Documents, …) must be deletable.
final class FileCopierACLTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // The source folders deny delete; clear every ACL so they can go.
        try run("/bin/chmod", "-R", "-N", tempDirectory.path)
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCopyDropsEveryoneDenyDeleteButKeepsOtherRules() throws {
        let source = tempDirectory.appendingPathComponent("Desktop")
        let inner = source.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: inner.appendingPathComponent("note.txt"))
        try run("/bin/chmod", "+a", "staff allow list", source.path)
        try run("/bin/chmod", "+a", "everyone deny delete", source.path)
        try run("/bin/chmod", "+a", "everyone deny delete", inner.path)

        let copy = tempDirectory.appendingPathComponent("Copy")
        try FileCopier.copy(source, to: copy, cancellation: CancellationFlag(), onProgress: { _ in })

        let copyACL = try acl(copy)
        XCTAssertFalse(copyACL.contains("deny delete"), copyACL)
        XCTAssertTrue(copyACL.contains("staff allow list"), copyACL)
        XCTAssertFalse(try acl(copy.appendingPathComponent("Documents")).contains("deny delete"))
        XCTAssertTrue(try acl(source).contains("everyone deny delete"), "The original keeps its protection")

        XCTAssertNoThrow(try FileManager.default.removeItem(at: copy))
    }

    func testAnEntryDenyingMoreThanDeleteKeepsTheRest() throws {
        let source = tempDirectory.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try run("/bin/chmod", "+a", "everyone deny delete,writeattr", source.path)

        let copy = tempDirectory.appendingPathComponent("Copy")
        try FileCopier.copy(source, to: copy, cancellation: CancellationFlag(), onProgress: { _ in })

        let copyACL = try acl(copy)
        XCTAssertTrue(copyACL.contains("everyone deny writeattr"), copyACL)
        XCTAssertFalse(copyACL.contains("delete"), copyACL)
    }

    /// `ls -led`'s ACL lines.
    private func acl(_ url: URL) throws -> String {
        try run("/bin/ls", "-led", url.path)
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FileCopierACLTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}
#endif
