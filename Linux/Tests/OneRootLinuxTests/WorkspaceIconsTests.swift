import XCTest
@testable import OneRootLinux
@testable import OneRoot

final class WorkspaceIconsTests: XCTestCase {
    func testEveryMacChoiceHasALinuxIcon() {
        for symbol in Workspace.symbolChoices {
            XCTAssertNotNil(WorkspaceIcons.linuxNames[symbol], symbol)
        }
    }

    func testUnknownSymbolFallsBack() {
        XCTAssertEqual(WorkspaceIcons.iconName(for: "unheard.of"), WorkspaceIcons.fallback)
    }
}
