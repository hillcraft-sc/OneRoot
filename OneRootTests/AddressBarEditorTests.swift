import XCTest
@testable import OneRoot

final class AddressBarEditorTests: XCTestCase {
    private let home = "/Users/test"

    private func breadcrumbs() -> AddressBarEditor {
        AddressBarEditor(alwaysTextField: false, currentPath: home)
    }

    func testStartsAsBreadcrumbsShowingTheCurrentPath() {
        let editor = breadcrumbs()

        XCTAssertEqual(editor.mode, .breadcrumbs)
        XCTAssertEqual(editor.text, home)
    }

    func testBeginEditingStartsFromTheCurrentPath() {
        var editor = breadcrumbs()
        editor.text = "/leftover"

        editor.begin(currentPath: home)

        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.text, home)
        XCTAssertNil(editor.errorMessage)
    }

    func testCancelReturnsToBreadcrumbsAndDropsTheTypedText() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        editor.text = "/Applic"

        editor.cancel(currentPath: home)

        XCTAssertEqual(editor.mode, .breadcrumbs)
        XCTAssertEqual(editor.text, home)
    }

    func testAValidPathNavigatesButStaysEditingUntilFinished() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        let target = URL(fileURLWithPath: "/Applications")

        XCTAssertEqual(editor.submit(.success(.local(target))), .navigate(target))
        XCTAssertTrue(editor.isEditing)

        editor.finish(currentPath: target.path)
        XCTAssertEqual(editor.mode, .breadcrumbs)
        XCTAssertEqual(editor.text, "/Applications")
    }

    func testAnInvalidPathStaysEditingWithTheReasonAndNeverNavigates() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        editor.text = "/nope"

        XCTAssertEqual(editor.submit(.failure(.notFound("/nope"))), .stay)
        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.text, "/nope", "what was typed stays, to fix it")
        XCTAssertEqual(editor.errorMessage, PathResolutionError.notFound("/nope").errorDescription)

        editor.textEdited()
        XCTAssertNil(editor.errorMessage)
    }

    func testANetworkAddressConnectsAndAFailedMountStaysEditing() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        let share = URL(string: "smb://server/share")!

        XCTAssertEqual(editor.submit(.success(.networkShare(share))), .connect(share))
        editor.connectionFailed("Couldn't connect.")

        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.errorMessage, "Couldn't connect.")
    }

    func testPathChangesElsewhereDontOverwriteTyping() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        editor.text = "/Users/te"

        editor.currentPathChanged(to: "/Library", isTyping: true)
        XCTAssertEqual(editor.text, "/Users/te")

        editor.currentPathChanged(to: "/Library", isTyping: false)
        XCTAssertEqual(editor.text, "/Library")
    }

    func testSwitchingTabsWhileEditingDropsTheOldTabsText() {
        var editor = breadcrumbs()
        editor.begin(currentPath: home)
        editor.text = "/half/typed"

        editor.paneChanged(currentPath: "/Volumes/USB")

        XCTAssertEqual(editor.mode, .breadcrumbs)
        XCTAssertEqual(editor.text, "/Volumes/USB")
    }

    func testTextFieldStyleNeverLeavesEditing() {
        var editor = AddressBarEditor(alwaysTextField: true, currentPath: home)
        XCTAssertTrue(editor.isEditing)

        editor.cancel(currentPath: home)
        editor.paneChanged(currentPath: "/Library")

        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.text, "/Library")
    }
}
