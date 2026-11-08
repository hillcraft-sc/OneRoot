import XCTest
@testable import OneRoot

final class ArchiveProcessRegistryTests: XCTestCase {
    func testTerminateAllStopsARunningProcess() throws {
        let registry = ArchiveProcessRegistry.shared
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        XCTAssertTrue(process.isRunning)

        registry.register(process)
        XCTAssertTrue(registry.hasRunningProcesses)

        registry.terminateAll()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(process.isRunning, "terminateAll() should have stopped the process")

        registry.unregister(process)
        XCTAssertFalse(registry.hasRunningProcesses)
    }

    func testUnregisteringAProcessThatNeverRanIsANoOp() {
        let registry = ArchiveProcessRegistry.shared
        let process = Process()

        registry.unregister(process)

        XCTAssertFalse(registry.hasRunningProcesses)
    }
}
