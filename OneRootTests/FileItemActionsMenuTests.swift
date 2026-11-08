import AppKit
import XCTest
@testable import OneRoot

/// The file list's context menu, built the way AppKit builds it, with its
/// items fired the way AppKit fires them — a dead selector (as once shipped
/// in the tab menu) fails here instead of silently doing nothing.
@MainActor
final class FileItemActionsMenuTests: XCTestCase {
    /// Kept for the test's length: menu items hold their target weakly,
    /// as the file views keep theirs.
    private var actions: FileItemActions?
    private func node(_ name: String, tags: [String]) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: false, size: 1, modificationDate: nil, kind: nil, tags: tags)
    }

    private func tagsSubmenu(for nodes: [FileNode], suggestions: [String], onSetTag: @escaping (String, Bool, [FileNode]) -> Void) throws -> NSMenu {
        let actions = FileItemActions()
        self.actions = actions
        actions.selectionProvider = { nodes }
        actions.tagSuggestions = { suggestions }
        actions.onSetTag = onSetTag
        let menu = NSMenu()
        actions.menuNeedsUpdate(menu)
        return try XCTUnwrap(menu.items.first { $0.title == "Tags" }?.submenu)
    }

    private func fire(_ item: NSMenuItem) throws {
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(target.responds(to: action), "\(item.title): its target doesn't answer \(action)")
        target.perform(action, with: item)
    }

    func testTagsShowWhetherAllSomeOrNoneOfTheSelectionHaveThem() throws {
        let nodes = [node("a", tags: ["Red", "Work"]), node("b", tags: ["Red"])]
        let submenu = try tagsSubmenu(for: nodes, suggestions: ["Red", "Blue"]) { _, _, _ in }
        let states = Dictionary(uniqueKeysWithValues: submenu.items.map { ($0.title, $0.state) })
        XCTAssertEqual(states["Red"], .on)
        XCTAssertEqual(states["Work"], .mixed)
        XCTAssertEqual(states["Blue"], .off)
    }

    func testChoosingATagAddsItUnlessEveryItemHasIt() throws {
        let nodes = [node("a", tags: ["Red", "Work"]), node("b", tags: ["Red"])]
        var calls: [(String, Bool)] = []
        let submenu = try tagsSubmenu(for: nodes, suggestions: ["Blue"]) { tag, adding, chosen in
            calls.append((tag, adding))
            XCTAssertEqual(chosen.map(\.name), ["a", "b"])
        }
        for title in ["Red", "Work", "Blue"] {
            try fire(try XCTUnwrap(submenu.items.first { $0.title == title }))
        }
        XCTAssertEqual(calls.map(\.0), ["Red", "Work", "Blue"])
        XCTAssertEqual(calls.map(\.1), [false, true, true])
    }
}
