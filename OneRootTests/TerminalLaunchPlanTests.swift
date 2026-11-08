import XCTest
@testable import OneRoot

final class TerminalLaunchPlanTests: XCTestCase {
    func testNoFolderArgumentUsesDocumentOpenWhetherOrNotRunning() {
        XCTAssertEqual(TerminalLaunchPlan.plan(hasWorkingDirectoryFlag: false, isRunning: false), .documentOpen)
        XCTAssertEqual(TerminalLaunchPlan.plan(hasWorkingDirectoryFlag: false, isRunning: true), .documentOpen)
    }

    func testRunningAppJustGetsTheFolderArgument() {
        XCTAssertEqual(TerminalLaunchPlan.plan(hasWorkingDirectoryFlag: true, isRunning: true), .sendArguments)
    }

    func testNotRunningAppIsStartedFirstThenGivenTheFolder() {
        XCTAssertEqual(TerminalLaunchPlan.plan(hasWorkingDirectoryFlag: true, isRunning: false), .launchThenSendArguments)
    }
}
