import XCTest
@testable import OneRoot

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(service: WorkspaceService(defaults: defaults))
    }

    func testSavedWorkspacesComeBack() {
        let store = makeStore()
        let workspace = Workspace(name: "Phoenix", symbolName: "hammer", folders: [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/Volumes/NAS/b")])
        store.save(workspace)

        XCTAssertEqual(makeStore().workspaces, [workspace])
    }

    func testSavingAgainReplacesAndDeleteRemoves() {
        let store = makeStore()
        var workspace = Workspace(name: "Phoenix")
        store.save(workspace)
        workspace.name = "Phoenix 2026"
        store.save(workspace)
        XCTAssertEqual(store.workspaces.map(\.name), ["Phoenix 2026"])

        store.delete(workspace.id)
        XCTAssertTrue(makeStore().workspaces.isEmpty)
    }

    func testAnEmptyNameGetsAUniqueDefault() {
        let store = makeStore()
        store.save(Workspace(name: "  "))
        store.save(Workspace(name: ""))
        XCTAssertEqual(store.workspaces.map(\.name), ["New Workspace", "New Workspace 2"])
    }

    func testAddingFoldersSkipsOnesAlreadyThere() {
        let store = makeStore()
        let workspace = Workspace(name: "W", folders: [URL(fileURLWithPath: "/a")])
        store.save(workspace)

        store.addFolders([URL(fileURLWithPath: "/a/"), URL(fileURLWithPath: "/b")], to: workspace.id)

        XCTAssertEqual(store.workspace(workspace.id)?.folders.map(\.path), ["/a", "/b"])
    }

    func testAFolderInsideOneAlreadyThereIsNotAdded() {
        let store = makeStore()
        let workspace = Workspace(name: "W", folders: [URL(fileURLWithPath: "/a")])
        store.save(workspace)

        store.addFolders([URL(fileURLWithPath: "/a/sub/deeper"), URL(fileURLWithPath: "/ab")], to: workspace.id)

        XCTAssertEqual(store.workspace(workspace.id)?.folders.map(\.path), ["/a", "/ab"])
    }

    func testCreateWithAFolderNamesItAfterTheFolder() {
        let store = makeStore()
        let first = store.create(with: URL(fileURLWithPath: "/x/Phoenix"))
        let second = store.create(with: URL(fileURLWithPath: "/y/Phoenix"))
        XCTAssertEqual(first.name, "Phoenix")
        XCTAssertEqual(second.name, "Phoenix 2")
    }

    func testContainsTheFoldersAndWhatsInsideThem() {
        let workspace = Workspace(name: "W", folders: [URL(fileURLWithPath: "/a/docs"), URL(fileURLWithPath: "/Volumes/NAS/design")])
        XCTAssertTrue(workspace.contains(URL(fileURLWithPath: "/a/docs")))
        XCTAssertTrue(workspace.contains(URL(fileURLWithPath: "/Volumes/NAS/design/final")))
        XCTAssertFalse(workspace.contains(URL(fileURLWithPath: "/a")))
        XCTAssertFalse(workspace.contains(URL(fileURLWithPath: "/a/docs-old")))
    }

    func testRootsKeepOrderAndTellSameNamedFoldersApart() {
        let workspace = Workspace(name: "W", folders: [
            URL(fileURLWithPath: "/p/Phoenix/Design"),
            URL(fileURLWithPath: "/a/Archive/Design"),
            URL(fileURLWithPath: "/r/Repository"),
        ])
        XCTAssertEqual(workspace.hierarchyRoots.map(\.name), ["Design (Phoenix)", "Design (Archive)", "Repository"])
        XCTAssertEqual(workspace.hierarchyRoots.map(\.url.path), ["/p/Phoenix/Design", "/a/Archive/Design", "/r/Repository"])
    }
}
