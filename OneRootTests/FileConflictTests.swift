import XCTest
@testable import OneRoot

/// Up-front conflict checking for copy/move: one question for every
/// collision, per-item answers, Cancel, and Replace sending the old item
/// to the Trash (a fake one here — never the real Trash).
final class FileConflictTests: XCTestCase {
    private var service = FileSystemService()
    private var tempDirectory: URL!
    private var destination: URL!
    private var fakeTrash: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        fakeTrash = tempDirectory.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        service.trashItem = FileSystemServiceTests.fakeTrashItem(into: fakeTrash)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ text: String, _ name: String, in folder: URL? = nil) throws -> URL {
        let folder = folder ?? tempDirectory!
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(name), encoding: .utf8)
    }

    private func destinationNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
    }

    /// Collects the requests it's asked, answering each with `answer`.
    private final class Recorder: @unchecked Sendable {
        var requests: [FileConflictRequest] = []
        var answer: (FileConflictRequest) -> FileConflictAnswer
        init(_ answer: @escaping (FileConflictRequest) -> FileConflictAnswer) { self.answer = answer }
        func resolve(_ request: FileConflictRequest) async -> FileConflictAnswer {
            requests.append(request)
            return answer(request)
        }
    }

    // MARK: One question up front

    func testAllConflictsAreAskedAboutOnceBeforeAnythingIsCopied() async throws {
        let sources = try ["a", "b", "c", "d"].map { try write("new \($0)", "\($0).txt") }
        for name in ["a", "b", "c"] { try write("old \(name)", "\(name).txt", in: destination) }
        let destination = self.destination!
        var namesWhenAsked: [String] = []
        let recorder = Recorder { request in
            namesWhenAsked = (try? FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()) ?? []
            return .all(.skip, for: request.conflicts)
        }

        try await service.copyItems(sources, to: destination, resolveConflicts: recorder.resolve)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].conflicts.map(\.name), ["a.txt", "b.txt", "c.txt"])
        XCTAssertEqual(recorder.requests[0].itemCount, 4)
        XCTAssertFalse(recorder.requests[0].isMove)
        XCTAssertEqual(namesWhenAsked, ["a.txt", "b.txt", "c.txt"], "nothing is copied before the answer")
        XCTAssertEqual(try read("a.txt"), "old a")
        XCTAssertEqual(try read("d.txt"), "new d", "items without a conflict still go")
    }

    func testEachConflictGetsItsOwnAnswer() async throws {
        let a = try write("new a", "a.txt")
        let b = try write("new b", "b.txt")
        let c = try write("new c", "c.txt")
        for name in ["a", "b", "c"] { try write("old \(name)", "\(name).txt", in: destination) }

        try await service.copyItems([a, b, c], to: destination) { _ in
            .resolve([a: .replace, b: .keepBoth, c: .skip])
        }

        XCTAssertEqual(try read("a.txt"), "new a")
        XCTAssertEqual(try read("b.txt"), "old b")
        XCTAssertEqual(try read("b (2).txt"), "new b")
        XCTAssertEqual(try read("c.txt"), "old c")
    }

    func testAConflictLeftOutOfTheAnswerIsSkipped() async throws {
        let a = try write("new a", "a.txt")
        try write("old a", "a.txt", in: destination)

        try await service.copyItems([a], to: destination) { _ in .resolve([:]) }

        XCTAssertEqual(try read("a.txt"), "old a")
        XCTAssertEqual(try destinationNames(), ["a.txt"])
    }

    func testCancelUpFrontCopiesNothing() async throws {
        let a = try write("new a", "a.txt")
        let b = try write("new b", "b.txt")
        try write("old a", "a.txt", in: destination)
        let log = FileChangeLog()

        try await service.copyItems([a, b], to: destination, changeLog: log) { _ in .cancel }

        XCTAssertEqual(try destinationNames(), ["a.txt"], "not even the item without a conflict")
        XCTAssertEqual(try read("a.txt"), "old a")
        XCTAssertTrue(log.changes.isEmpty)
    }

    func testCancelUpFrontMovesNothing() async throws {
        let a = try write("new a", "a.txt")
        let b = try write("new b", "b.txt")
        try write("old a", "a.txt", in: destination)

        try await service.moveItems([a, b], to: destination) { _ in .cancel }

        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertEqual(try destinationNames(), ["a.txt"])
    }

    func testNoConflictsMeansNoQuestion() async throws {
        let a = try write("new a", "a.txt")
        let recorder = Recorder { _ in .cancel }

        try await service.copyItems([a], to: destination, resolveConflicts: recorder.resolve)

        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(try read("a.txt"), "new a")
    }

    func testACollisionThatAppearsMidwayIsAskedAboutOnItsOwn() async throws {
        // Same name from two folders: the second only collides once the
        // first has been copied.
        let first = try write("first", "x.txt", in: tempDirectory.appendingPathComponent("one"))
        let second = try write("second", "x.txt", in: tempDirectory.appendingPathComponent("two"))
        let recorder = Recorder { .all(.keepBoth, for: $0.conflicts) }

        try await service.copyItems([first, second], to: destination, resolveConflicts: recorder.resolve)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.conflicts.map(\.source), [second])
        XCTAssertEqual(try read("x.txt"), "first")
        XCTAssertEqual(try read("x (2).txt"), "second")
    }

    func testCancellingAMidwayQuestionStopsTheOperation() async throws {
        let first = try write("first", "x.txt", in: tempDirectory.appendingPathComponent("one"))
        let second = try write("second", "x.txt", in: tempDirectory.appendingPathComponent("two"))

        do {
            try await service.copyItems([first, second], to: destination) { _ in .cancel }
            XCTFail("expected CancellationError")
        } catch is CancellationError {}

        XCTAssertEqual(try read("x.txt"), "first")
        XCTAssertEqual(try destinationNames(), ["x.txt"])
    }

    func testItsOwnFolderIsNotAConflict() {
        let url = tempDirectory.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: url.path, contents: Data())

        XCTAssertTrue(FileSystemService.conflicts(for: [url], in: tempDirectory).isEmpty)
    }

    // MARK: Replace goes to the Trash

    func testReplaceMovesTheExistingItemToTheTrashAndLogsItForUndo() async throws {
        let source = try write("new", "a.txt")
        let existing = try write("old", "a.txt", in: destination)
        let log = FileChangeLog()

        try await service.copyItems([source], to: destination, changeLog: log) { _ in .resolve([source: .replace]) }

        XCTAssertEqual(try read("a.txt"), "new")
        XCTAssertEqual(try destinationNames(), ["a.txt"], "no staging leftovers")
        let trashed = try FileManager.default.contentsOfDirectory(at: fakeTrash, includingPropertiesForKeys: nil)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(try String(contentsOf: trashed[0], encoding: .utf8), "old")
        // The old item's trashing first, so Undo removes the new one before
        // putting the old one back.
        XCTAssertEqual(log.changes.count, 2)
        guard case .trashed(let original, let trashedAt) = log.changes[0] else {
            return XCTFail("expected the replaced item's trashing first, got \(log.changes)")
        }
        XCTAssertEqual(original.standardizedFileURL, existing.standardizedFileURL)
        XCTAssertEqual(trashedAt.standardizedFileURL, trashed[0].standardizedFileURL)
        XCTAssertEqual(log.changes[1], .created(destination.appendingPathComponent("a.txt")))
    }

    func testMoveWithReplaceLogsTheTrashingThenTheMove() async throws {
        let source = try write("new", "a.txt")
        try write("old", "a.txt", in: destination)
        let log = FileChangeLog()

        try await service.moveItems([source], to: destination, changeLog: log) { .all(.replace, for: $0.conflicts) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try read("a.txt"), "new")
        guard log.changes.count == 2, case .trashed = log.changes[0] else {
            return XCTFail("expected [trashed, moved], got \(log.changes)")
        }
        XCTAssertEqual(log.changes[1], .moved(from: source, to: destination.appendingPathComponent("a.txt")))
    }

    func testReplaceOnAVolumeWithoutTrashStillReplaces() async throws {
        service.trashItem = { _ in throw CocoaError(.featureUnsupported) }
        let source = try write("new", "a.txt")
        try write("old", "a.txt", in: destination)
        let log = FileChangeLog()

        try await service.copyItems([source], to: destination, changeLog: log) { _ in .resolve([source: .replace]) }

        XCTAssertEqual(try read("a.txt"), "new")
        XCTAssertEqual(try destinationNames(), ["a.txt"], "the old item is deleted, no hidden leftover")
        XCTAssertEqual(log.changes, [.created(destination.appendingPathComponent("a.txt"))], "nothing to put back")
    }

    func testReplaceLeavesTheOriginalWhenTheCopyFails() async throws {
        let source = try write("new", "a.txt")
        try write("old", "a.txt", in: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path) }

        do {
            try await service.copyItems([source], to: destination) { _ in .resolve([source: .replace]) }
            XCTFail("copying an unreadable file should throw")
        } catch {}

        XCTAssertEqual(try read("a.txt"), "old")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fakeTrash.path).isEmpty, "nothing trashed")
    }

    // MARK: Metadata

    func testNewerComparesModificationDates() {
        let now = Date()
        func item(incoming: Date?, existing: Date?) -> FileConflictItem {
            FileConflictItem(
                source: URL(fileURLWithPath: "/a"), existing: URL(fileURLWithPath: "/b"),
                incoming: .init(isDirectory: false, modified: incoming, size: 1),
                current: .init(isDirectory: false, modified: existing, size: 1)
            )
        }
        XCTAssertEqual(item(incoming: now, existing: now.addingTimeInterval(-60)).newer, .incoming)
        XCTAssertEqual(item(incoming: now.addingTimeInterval(-60), existing: now).newer, .existing)
        XCTAssertNil(item(incoming: now, existing: now.addingTimeInterval(0.5)).newer, "within a second is the same")
        XCTAssertNil(item(incoming: nil, existing: now).newer)
    }

    func testConflictsReadSizesForFilesOnly() throws {
        let file = try write("12345", "a.txt")
        try write("1", "a.txt", in: destination)
        let folder = tempDirectory.appendingPathComponent("F", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("F"), withIntermediateDirectories: true)

        let conflicts = FileSystemService.conflicts(for: [file, folder], in: destination)

        XCTAssertEqual(conflicts.count, 2)
        XCTAssertEqual(conflicts[0].incoming.size, 5)
        XCTAssertEqual(conflicts[0].current.size, 1)
        XCTAssertTrue(conflicts[1].incoming.isDirectory)
        XCTAssertNil(conflicts[1].incoming.size)
    }

    // MARK: Queue

    @MainActor
    func testQueueAnswersInOrderAndIgnoresStaleAnswers() async {
        let queue = FileConflictQueue()
        var shown: [UUID?] = []
        queue.onChange = { shown.append($0?.id) }
        let first = FileConflictRequest(conflicts: [], itemCount: 1, destination: destination, isMove: false)
        let second = FileConflictRequest(conflicts: [], itemCount: 1, destination: destination, isMove: false)

        let firstAnswer = Task { await queue.ask(first) }
        let secondAnswer = Task { await queue.ask(second) }
        while queue.current == nil || shown.isEmpty { await Task.yield() }
        // Let the second ask enqueue too.
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(queue.current?.id, first.id)
        queue.answer(.cancel, to: second.id) // not current: ignored
        XCTAssertEqual(queue.current?.id, first.id)
        queue.answer(.resolve([:]), to: first.id)
        XCTAssertEqual(queue.current?.id, second.id)
        queue.answer(.resolve([:]), to: first.id) // stale: ignored
        XCTAssertEqual(queue.current?.id, second.id)
        queue.answer(.cancel, to: second.id)

        let answers = (await firstAnswer.value, await secondAnswer.value)
        XCTAssertEqual(answers.0, .resolve([:]))
        XCTAssertEqual(answers.1, .cancel)
        XCTAssertNil(queue.current)
        XCTAssertEqual(shown, [first.id, second.id, nil])
    }
}
