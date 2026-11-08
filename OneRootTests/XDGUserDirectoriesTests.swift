import XCTest
@testable import OneRoot

final class XDGUserDirectoriesTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/home/test", isDirectory: true)

    func testReadsHomeRelativeAndAbsoluteFoldersInSidebarOrder() {
        let file = """
        # This file is written by xdg-user-dirs-update
        XDG_VIDEOS_DIR="$HOME/Videos"
        XDG_DESKTOP_DIR="$HOME/Desktop"
        XDG_DOWNLOAD_DIR="/data/Downloads"
        XDG_TEMPLATES_DIR="$HOME/Templates"
        XDG_PICTURES_DIR="$HOME/Bilder"
        """
        XCTAssertEqual(XDGUserDirectories.folders(in: file, home: home).map(\.path), [
            "/home/test/Desktop", "/data/Downloads", "/home/test/Bilder", "/home/test/Videos",
        ])
    }

    func testAFolderSetToHomeIsTurnedOff() {
        let file = """
        XDG_DESKTOP_DIR="$HOME/"
        XDG_MUSIC_DIR="$HOME"
        XDG_DOCUMENTS_DIR="$HOME/Documents"
        """
        XCTAssertEqual(XDGUserDirectories.folders(in: file, home: home).map(\.path), ["/home/test/Documents"])
    }

    func testIgnoresRelativePathsCommentsAndOtherLines() {
        let file = """
        #XDG_DESKTOP_DIR="$HOME/Desktop"
        XDG_MUSIC_DIR="Music"
        SOMETHING_ELSE="$HOME/x"
        XDG_DOCUMENTS_DIR="$HOME/My \\"Docs\\""
        """
        XCTAssertEqual(XDGUserDirectories.folders(in: file, home: home).map(\.path), ["/home/test/My \"Docs\""])
    }

    @MainActor
    func testUserFoldersFollowHomeInTheSidebar() {
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let viewModel = DestinationsViewModel(
            volumeService: NullVolumeProvider(),
            pinnedLocations: makeIsolatedPinnedLocationsStore(),
            homeURL: home,
            applicationsURL: nil,
            virtualLocations: [],
            userFolders: [documents]
        )
        let homeSection = viewModel.sections.first { $0.id == "home" }
        XCTAssertEqual(homeSection?.destinations.map(\.url), [home, documents])
        XCTAssertEqual(homeSection?.destinations.map(\.name), ["test", "Documents"])
        XCTAssertFalse(viewModel.allDestinations.contains { $0.kind == .applications })
    }
}
