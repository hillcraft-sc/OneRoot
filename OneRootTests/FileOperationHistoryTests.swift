import XCTest
@testable import OneRoot

@MainActor
final class FileOperationHistoryTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testFinishedOperationsMoveToRecentNewestFirst() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let first = center.begin(title: "Copying a", symbolName: "folder.fill", totalBytes: 1, cancel: {})
        let second = center.begin(title: "Copying b", symbolName: "folder.fill", totalBytes: 1, cancel: {})

        center.finish(first)
        center.finish(second, outcome: .cancelled)

        XCTAssertTrue(center.operations.isEmpty)
        XCTAssertEqual(center.recent.map(\.title), ["Copying b", "Copying a"])
        XCTAssertEqual(center.recent.map(\.outcome), [.cancelled, .succeeded])
    }

    func testCancelIsAcknowledgedAtOnceAndOnlyAskedOnce() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        var cancels = 0
        let id = center.begin(title: "Copying a", symbolName: "folder.fill", totalBytes: 1, cancel: { cancels += 1 })

        center.requestCancel(id)
        center.requestCancel(id)

        XCTAssertEqual(center.operations.first?.isCancelling, true)
        XCTAssertEqual(cancels, 1)
    }

    func testProgressInTheWindowSuppressesFloatingWindowsWhileAWindowIsOpen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FileOperationHistoryTests-\(UUID().uuidString)"))
        let center = FileOperationProgressCenter(defaults: defaults)
        center.windowBecameFront(7)
        XCTAssertTrue(center.showsFloatingWindows)

        defaults.set(true, forKey: FileOperationProgressCenter.showsProgressInWindowKey)
        XCTAssertFalse(center.showsFloatingWindows)

        // No main window left to show the card in: back to popups.
        center.windowClosed(7)
        XCTAssertNil(center.frontWindowNumber)
        XCTAssertTrue(center.showsFloatingWindows)
    }

    func testEachFinishedOperationIsAnnouncedOnce() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        var spoken: [String] = []
        center.announce = { spoken.append($0) }
        let a = center.begin(title: "Copying a", symbolName: "folder.fill", totalBytes: 1, cancel: {})
        let b = center.begin(title: "Moving b", symbolName: "folder.fill", totalBytes: 1, cancel: {})
        let c = center.begin(title: "Copying c", symbolName: "folder.fill", totalBytes: 1, cancel: {})

        center.finish(a)
        center.finish(b, outcome: .cancelled)
        center.finish(c, outcome: .failed(message: "The disk is full.", detail: nil))

        XCTAssertEqual(spoken, ["Copying a finished", "Moving b was cancelled", "Copying c failed: The disk is full."])
    }

    func testRecentIsCapped() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        for index in 0..<(FileOperationProgressCenter.maxRecent + 5) {
            center.finish(center.begin(title: "\(index)", symbolName: "folder.fill", totalBytes: 1, cancel: {}))
        }
        XCTAssertEqual(center.recent.count, FileOperationProgressCenter.maxRecent)
        XCTAssertEqual(center.recent.first?.title, "\(FileOperationProgressCenter.maxRecent + 4)")
    }

    func testRetryIsKeptOnlyForFailuresAndRunsOnce() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        var retries = 0
        center.finish(center.begin(title: "ok", symbolName: "folder.fill", totalBytes: 1, cancel: {}), retry: { retries += 1 })
        let failed = center.begin(title: "failed", symbolName: "folder.fill", totalBytes: 1, cancel: {})
        center.finish(failed, outcome: .failed(message: "No", detail: nil), retry: { retries += 1 })

        XCTAssertNil(center.recent.first { $0.title == "ok" }?.retry)
        center.retry(failed)

        XCTAssertEqual(retries, 1)
        XCTAssertNil(center.recent.first { $0.id == failed }, "Retrying replaces the failed entry")
    }

    func testFailuresCountUntilTheCardIsSeen() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        center.windowBecameFront(7)
        center.finish(center.begin(title: "x", symbolName: "folder.fill", totalBytes: 1, cancel: {}), outcome: .failed(message: "No", detail: nil))
        XCTAssertEqual(center.unseenFailureCount, 1)

        center.setCardShowing(true, inWindow: 7)
        XCTAssertEqual(center.unseenFailureCount, 0)

        // Failing while the card is in front is seen right away.
        center.finish(center.begin(title: "y", symbolName: "folder.fill", totalBytes: 1, cancel: {}), outcome: .failed(message: "No", detail: nil))
        XCTAssertEqual(center.unseenFailureCount, 0)
    }

    func testFloatingWindowsOnlyWhileTheFrontWindowHidesTheCard() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        XCTAssertTrue(center.showsFloatingWindows)
        center.windowBecameFront(1)
        center.setCardShowing(true, inWindow: 2)
        XCTAssertTrue(center.showsFloatingWindows)
        center.setCardShowing(true, inWindow: 1)
        XCTAssertFalse(center.showsFloatingWindows)
        center.setCardShowing(false, inWindow: 1)
        XCTAssertTrue(center.showsFloatingWindows)
    }

    func testFailureDetailSaysHowFarItGotAndTheSystemError() {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
            NSLocalizedFailureReasonErrorKey: "You don't have permission.",
        ])
        let outcome = FileOperationOutcome.failure(FileSystemError.cannotCopy("a.txt", underlying: underlying), finished: 2, of: 5)

        guard case .failed(let message, let detail) = outcome else { return XCTFail("Expected a failure") }
        XCTAssertTrue(message.contains("a.txt"))
        XCTAssertEqual(detail?.contains("2 of 5 items finished"), true)
        XCTAssertEqual(detail?.contains("You don't have permission."), true)
        XCTAssertEqual(detail?.contains("NSCocoaErrorDomain \(NSFileWriteNoPermissionError)"), true)
    }

    func testAFailedCopyOffersRetryForTheItemsThatDidNotFinish() async throws {
        let source = tempDirectory.appendingPathComponent("source")
        let destination = tempDirectory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let first = source.appendingPathComponent("first.txt")
        let missing = source.appendingPathComponent("missing.txt")
        let last = source.appendingPathComponent("last.txt")
        try Data("1".utf8).write(to: first)
        try Data("3".utf8).write(to: last)

        var retried: [URL]?
        do {
            try await FileSystemService().copyItems(
                [first, missing, last],
                to: destination,
                onConflict: { _ in .skip },
                retry: { retried = $0 }
            )
            XCTFail("Copying a missing file should fail")
        } catch {}

        let record = try XCTUnwrap(FileOperationProgressCenter.shared.recent.first)
        guard case .failed = record.outcome else { return XCTFail("Expected a failure") }
        FileOperationProgressCenter.shared.retry(record.id)

        XCTAssertEqual(retried, [missing, last])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("first.txt").path))
    }

    func testARecordKeepsWhereItWentAndHowFarItGot() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let source = URL(fileURLWithPath: "/tmp/source")
        let destination = URL(fileURLWithPath: "/tmp/destination")
        let id = center.begin(title: "Copying 4 items", symbolName: "folder.fill", totalBytes: 400, sourceFolder: source, destinationFolder: destination, itemCount: 4, cancel: {})
        center.setCurrentItem(id, index: 2, name: "c.txt")
        center.update(id, completedBytes: 250)

        center.finish(id, outcome: .cancelled, finishedItems: 2)

        let record = center.recent[0]
        XCTAssertEqual(record.sourceFolder, source)
        XCTAssertEqual(record.destinationFolder, destination)
        XCTAssertEqual(record.finishedItems, 2)
        XCTAssertEqual(record.itemCount, 4)
        XCTAssertEqual(record.completedBytes, 250)
        XCTAssertEqual(record.totalBytes, 400)
        XCTAssertTrue(FileOperationText.summary(for: record).hasPrefix("Cancelled after 2 of 4 items"))
    }

    func testCurrentItemAndRouteText() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let id = center.begin(title: "t", symbolName: "folder.fill", totalBytes: 1, itemCount: 3, cancel: {})
        XCTAssertNil(FileOperationText.currentItem(for: center.operations[0]))
        center.setCurrentItem(id, index: 1, name: "b.txt")
        XCTAssertEqual(FileOperationText.currentItem(for: center.operations[0]), "Item 2 of 3: \u{201C}b.txt\u{201D}")

        XCTAssertEqual(
            FileOperationText.route(source: URL(fileURLWithPath: "/Volumes/USB"), destination: URL(fileURLWithPath: "/tmp")),
            "From /Volumes/USB to /tmp"
        )
        XCTAssertNil(FileOperationText.route(source: nil, destination: nil))
    }

    func testASuccessCountsEveryItem() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        center.finish(center.begin(title: "t", symbolName: "folder.fill", totalBytes: 10, itemCount: 3, cancel: {}))
        XCTAssertEqual(center.recent[0].finishedItems, 3)
        XCTAssertTrue(FileOperationText.summary(for: center.recent[0]).hasPrefix("Done \u{00B7} 3 items"))
    }

    func testClearingFinishedKeepsFailuresAndViceVersa() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        center.finish(center.begin(title: "done", symbolName: "folder.fill", totalBytes: 1, cancel: {}))
        center.finish(center.begin(title: "failed", symbolName: "folder.fill", totalBytes: 1, cancel: {}), outcome: .failed(message: "No", detail: nil))

        center.clearRecent(failures: false)
        XCTAssertEqual(center.recent.map(\.title), ["failed"])
        center.clearRecent(failures: true)
        XCTAssertTrue(center.recent.isEmpty)
    }

    func testATrashThatPartlyFailsIsRecordedWithRetryForTheRest() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let kept = URL(fileURLWithPath: "/tmp/a/Desktop")
        let gone = URL(fileURLWithPath: "/tmp/a/b.txt")
        var result = TrashResult()
        result.trashed = [gone]
        result.failures = [(kept, FileSystemError.cannotTrash(kept, underlying: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))]
        var retried: [URL]?

        center.recordTrash([kept, gone], result: result, retry: { retried = $0 })

        let record = center.recent[0]
        XCTAssertEqual(record.title, "Moving 2 items to the Trash")
        XCTAssertTrue(record.outcome.isFailure)
        XCTAssertEqual(record.finishedItems, 1)
        XCTAssertEqual(record.sourceFolder?.path, "/tmp/a")
        center.retry(record.id)
        XCTAssertEqual(retried, [kept])
    }

    func testASuccessfulTrashHasNoRetryAndNoTime() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let file = URL(fileURLWithPath: "/tmp/a/b.txt")
        var result = TrashResult()
        result.trashed = [file]

        center.recordTrash([file], result: result, retry: { _ in })

        XCTAssertNil(center.recent[0].retry)
        XCTAssertFalse(FileOperationText.summary(for: center.recent[0]).contains(" in "))
    }

    // MARK: Pause

    private final class FakePause: PauseControl, @unchecked Sendable {
        var calls: [String] = []
        func pause() { calls.append("pause") }
        func resume() { calls.append("resume") }
    }

    func testPauseAndResumeReachTheOperation() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let control = FakePause()
        let id = center.begin(title: "Copying a", symbolName: "folder.fill", totalBytes: 10, pauseControl: control, cancel: {})

        center.requestPause(id)
        XCTAssertTrue(center.operations[0].isPaused)
        center.requestPause(id) // already paused: nothing more
        center.requestResume(id)

        XCTAssertFalse(center.operations[0].isPaused)
        XCTAssertEqual(control.calls, ["pause", "resume"])
    }

    func testOperationsWithoutAPauseControlCantPause() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        let id = center.begin(title: "Converting", symbolName: "wand.and.stars", totalBytes: 1, cancel: {})

        center.requestPause(id)

        XCTAssertFalse(center.operations[0].canPause)
        XCTAssertFalse(center.operations[0].isPaused)
    }

    func testCancellingWhilePausedEndsThePauseFirst() {
        let center = FileOperationProgressCenter(defaults: .isolatedForTests())
        var cancelled = false
        let id = center.begin(title: "Copying a", symbolName: "folder.fill", totalBytes: 10, pauseControl: FakePause(), cancel: { cancelled = true })

        center.requestPause(id)
        center.requestCancel(id)

        XCTAssertTrue(cancelled)
        XCTAssertFalse(center.operations[0].isPaused)
        XCTAssertFalse(center.operations[0].canPause, "no Pause once cancelling")
    }

    func testPausedTimeDoesntCountTowardSpeed() {
        let start = Date(timeIntervalSince1970: 1_000)
        var operation = FileOperationProgress(
            title: "Copying a", symbolName: "folder.fill", completedBytes: 10_000_000, totalBytes: 100_000_000,
            isIndeterminate: false, isPreparing: false, startDate: start, beganAt: start,
            itemCount: 1, currentItemIndex: 0, cancel: {}
        )
        operation.pausedDuration = 50
        operation.pausedSince = start.addingTimeInterval(90)
        operation.isPaused = true
        let now = start.addingTimeInterval(100)

        XCTAssertEqual(operation.activeElapsed(at: now), 40, accuracy: 0.001)
        XCTAssertTrue(FileOperationText.status(for: operation, now: now).hasPrefix("Paused"))
        XCTAssertFalse(FileOperationText.status(for: operation, now: now).contains("/s"), "no speed while paused")
    }

    func testSpeedAndTimeLeftFollowTheLastTenSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        var operation = FileOperationProgress(
            title: "Copying a", symbolName: "folder.fill", completedBytes: 0, totalBytes: 600_000_000,
            isIndeterminate: false, isPreparing: false, startDate: start, beganAt: start,
            itemCount: 1, currentItemIndex: 0, cancel: {}
        )
        // 100 MB in the first 10 s, then only 1 MB/s for the next 20 s.
        operation.recordRateSample(bytes: 0, at: start)
        operation.recordRateSample(bytes: 100_000_000, at: start.addingTimeInterval(10))
        for second in 11...30 {
            operation.recordRateSample(bytes: 100_000_000 + Int64(second - 10) * 1_000_000, at: start.addingTimeInterval(TimeInterval(second)))
        }
        operation.completedBytes = 120_000_000
        let now = start.addingTimeInterval(30)

        XCTAssertEqual(operation.recentRate ?? 0, 1_000_000, accuracy: 1, "the slow last ten seconds, not the 4 MB/s average")
        let status = FileOperationText.status(for: operation, now: now)
        XCTAssertTrue(status.contains("1 MB/s"), status)
        XCTAssertTrue(status.contains("8 minutes"), "480 MB left at 1 MB/s: \(status)")
    }

    func testNoSpeedWhileNothingMoves() {
        let start = Date(timeIntervalSince1970: 1_000)
        var operation = FileOperationProgress(
            title: "Copying a", symbolName: "folder.fill", completedBytes: 50_000_000, totalBytes: 100_000_000,
            isIndeterminate: false, isPreparing: false, startDate: start, beganAt: start,
            itemCount: 1, currentItemIndex: 0, cancel: {}
        )
        for second in 0...10 {
            operation.recordRateSample(bytes: 50_000_000, at: start.addingTimeInterval(TimeInterval(second)))
        }

        let status = FileOperationText.status(for: operation, now: start.addingTimeInterval(10))
        XCTAssertFalse(status.contains("/s"), status)
        XCTAssertFalse(status.contains("About"), status)
    }

    // MARK: Volumes with no Trash

    private func noTrashFailure(_ url: URL) -> (url: URL, error: Error) {
        (url, FileSystemError.cannotTrash(url, underlying: NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)))
    }

    func testOnlyNoTrashFailuresCountAsWithoutTrash() {
        let share = URL(fileURLWithPath: "/tmp/share/a.mkv")
        let locked = URL(fileURLWithPath: "/tmp/a/locked")
        var result = TrashResult()
        result.failures = [
            noTrashFailure(share),
            (locked, FileSystemError.cannotTrash(locked, underlying: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))
        ]

        XCTAssertEqual(result.withoutTrash, [share])
        XCTAssertEqual(result.removingFailures([share]).failures.map(\.url), [locked])
    }

    func testItemsWithoutTrashAreDeletedOnceConfirmed() async throws {
        let file = tempDirectory.appendingPathComponent("a.metathumb")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        var result = TrashResult()
        result.failures = [noTrashFailure(file)]
        var asked: [URL]?

        let outcome = await TrashFallback.deleteItemsWithoutTrash(
            result, confirm: { asked = $0; return true }, fileSystemService: FileSystemService()
        )

        XCTAssertEqual(asked, [file])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(outcome.deleted, [file])
        XCTAssertTrue(outcome.result.failures.isEmpty)
        XCTAssertNil(outcome.errorMessage)
    }

    func testDecliningLeavesItemsWithoutTrashInPlaceAndUnreported() async throws {
        let file = tempDirectory.appendingPathComponent("a.metathumb")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        var result = TrashResult()
        result.failures = [noTrashFailure(file)]

        let outcome = await TrashFallback.deleteItemsWithoutTrash(
            result, confirm: { _ in false }, fileSystemService: FileSystemService()
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(outcome.deleted.isEmpty)
        XCTAssertEqual(outcome.result.failures.map(\.url), [file]) // Retry asks again
        XCTAssertNil(outcome.errorMessage)
    }

    func testNoPromptWhenEveryFailureHasATrash() async {
        let locked = URL(fileURLWithPath: "/tmp/a/locked")
        var result = TrashResult()
        result.failures = [(locked, FileSystemError.cannotTrash(locked, underlying: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))]
        var asked = false

        let outcome = await TrashFallback.deleteItemsWithoutTrash(
            result, confirm: { _ in asked = true; return true }, fileSystemService: FileSystemService()
        )

        XCTAssertFalse(asked)
        XCTAssertNotNil(outcome.errorMessage)
    }
}
