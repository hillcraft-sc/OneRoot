import XCTest
import Observation
@testable import OneRoot

/// Never emits — these tests drive `applyVolumes` directly instead of going
/// through the publisher, so they don't depend on real system volume state.
final class NullVolumeProvider: VolumeProviding {
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject { NSObject() }

    func eject(_ volume: VolumeInfo) -> Bool { true }
}

private final class FailingVolumeProvider: VolumeProviding {
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject { NSObject() }
    func eject(_ volume: VolumeInfo) -> Bool { false }
    func lastEjectFailure() -> String? { "umount: /mnt/nas: target is busy." }
}

private final class RecordingVolumeProvider: VolumeProviding {
    var ejectedURLs: [URL] = []
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject { NSObject() }
    func eject(_ volume: VolumeInfo) -> Bool {
        ejectedURLs.append(volume.url)
        return true
    }
}

func makeTestVolume(name: String, path: String, isEjectable: Bool = false, isLocal: Bool = true) -> VolumeInfo {
    VolumeInfo(
        url: URL(fileURLWithPath: path),
        name: name,
        isRemovable: isEjectable,
        isEjectable: isEjectable,
        availableCapacity: nil,
        totalCapacity: nil,
        isLocal: isLocal
    )
}

/// A pin store on a throwaway `UserDefaults` suite, so pins never leak
/// between tests or pick up the real app's.
@MainActor
func makeIsolatedPinnedLocationsStore() -> PinnedLocationsStore {
    PinnedLocationsStore(service: PinnedLocationsService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
}

@MainActor
final class DestinationsViewModelTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    private func makeViewModel(
        volumeService: VolumeProviding = NullVolumeProvider(),
        pins: PinnedLocationsStore? = nil,
        cloudStorageLocations: [URL] = [],
        trashURL: URL? = nil,
        userFolders: [URL] = []
    ) -> DestinationsViewModel {
        // The Mac's sidebar entries, on both platforms, so these tests
        // don't depend on where they run.
        DestinationsViewModel(
            volumeService: volumeService,
            pinnedLocations: pins ?? makeIsolatedPinnedLocationsStore(),
            cloudStorageLocations: cloudStorageLocations,
            trashURL: trashURL,
            homeURL: home,
            applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true),
            virtualLocations: [.recents, .shared],
            userFolders: userFolders
        )
    }

    private func section(_ id: String, in viewModel: DestinationsViewModel) -> DestinationSection? {
        viewModel.sections.first { $0.id == id }
    }

    func testSectionOrderWithEverythingPresent() {
        let pins = makeIsolatedPinnedLocationsStore()
        pins.toggle(URL(fileURLWithPath: "/Users/test/Projects"))
        let viewModel = makeViewModel(
            pins: pins,
            cloudStorageLocations: [URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox")],
            trashURL: URL(fileURLWithPath: "/Users/test/.Trash")
        )

        XCTAssertEqual(viewModel.sections.map(\.id), ["home", "pinned", "cloud", "locations", "special"])
    }

    func testPinnedAndCloudSectionsOnlyAppearWhenNonEmpty() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.sections.map(\.id), ["home", "locations"])
    }

    func testHomeAppearsOnceAtTheTopAndNotUnderLocations() {
        let viewModel = makeViewModel()

        // Home, then Recents and Shared (lists, not folders).
        XCTAssertEqual(section("home", in: viewModel)?.destinations.map(\.url), [home, VirtualLocation.recents.url, VirtualLocation.shared.url])
        XCTAssertEqual(section("home", in: viewModel)?.title, "")
        XCTAssertFalse(section("locations", in: viewModel)?.destinations.contains { $0.url == home } ?? true)
        XCTAssertEqual(viewModel.allDestinations.filter { $0.url == home }.count, 1)
    }

    func testLocationsListsBootVolumeThenApplicationsThenOtherVolumes() {
        let viewModel = makeViewModel()

        viewModel.applyVolumes([
            makeTestVolume(name: "Zeta", path: "/Volumes/Zeta"),
            makeTestVolume(name: "Macintosh HD", path: "/"),
            makeTestVolume(name: "Alpha", path: "/Volumes/Alpha"),
        ])

        XCTAssertEqual(section("locations", in: viewModel)?.destinations.map(\.name), ["Macintosh HD", "Applications", "Alpha", "Zeta"])
        XCTAssertEqual(section("locations", in: viewModel)?.destinations.map(\.kind), [.bootVolume, .applications, .volume, .volume])
    }

    func testNetworkVolumeKind() {
        let viewModel = makeViewModel()

        viewModel.applyVolumes([makeTestVolume(name: "share", path: "/Volumes/share", isLocal: false)])

        XCTAssertEqual(viewModel.allDestinations.first { $0.name == "share" }?.kind, .networkVolume)
    }

    func testRemovesVolumeWhenItUnmounts() {
        let viewModel = makeViewModel()
        let volume = makeTestVolume(name: "Test", path: "/Volumes/Test")

        viewModel.applyVolumes([volume])
        XCTAssertTrue(viewModel.allDestinations.contains { $0.url == volume.url })

        viewModel.applyVolumes([])
        XCTAssertFalse(viewModel.allDestinations.contains { $0.url == volume.url })
    }

    func testDoesNotRepublishAnUnchangedList() {
        let viewModel = makeViewModel()
        let volume = makeTestVolume(name: "Test", path: "/Volumes/Test")
        viewModel.applyVolumes([volume])
        var notified = false
        withObservationTracking { _ = viewModel.sections } onChange: { notified = true }

        viewModel.applyVolumes([volume])

        XCTAssertFalse(notified)
    }

    func testHasLoadedVolumesFlipsOnFirstVolumeList() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.hasLoadedVolumes)

        viewModel.applyVolumes([])

        XCTAssertTrue(viewModel.hasLoadedVolumes)
    }

    func testEjectableURLsCoverRemovableMediaAndNetworkShares() {
        let viewModel = makeViewModel()
        let usb = makeTestVolume(name: "USB", path: "/Volumes/USB", isEjectable: true)
        let share = makeTestVolume(name: "timemachine", path: "/Volumes/timemachine", isLocal: false)
        let internalDisk = makeTestVolume(name: "Macintosh HD", path: "/")

        viewModel.applyVolumes([usb, share, internalDisk])

        XCTAssertEqual(viewModel.ejectableURLs, [usb.url, share.url])
    }

    func testEjectUnmountsNetworkShare() async {
        let provider = RecordingVolumeProvider()
        let viewModel = makeViewModel(volumeService: provider)
        let share = makeTestVolume(name: "timemachine", path: "/Volumes/timemachine", isLocal: false)
        viewModel.applyVolumes([share])

        await viewModel.eject(at: share.url).value

        XCTAssertEqual(provider.ejectedURLs, [share.url])
    }

    func testFailedEjectSaysWhyInTheToolsOwnWords() async {
        let viewModel = makeViewModel(volumeService: FailingVolumeProvider())
        let share = makeTestVolume(name: "nas", path: "/mnt/nas", isLocal: false)
        viewModel.applyVolumes([share])

        await viewModel.eject(at: share.url).value

        XCTAssertTrue(viewModel.errorMessage?.contains("target is busy") == true, viewModel.errorMessage ?? "nil")
    }

    func testEjectIgnoresNonEjectableVolume() async {
        let provider = RecordingVolumeProvider()
        let viewModel = makeViewModel(volumeService: provider)
        viewModel.applyVolumes([makeTestVolume(name: "Macintosh HD", path: "/")])

        await viewModel.eject(at: URL(fileURLWithPath: "/")).value

        XCTAssertTrue(provider.ejectedURLs.isEmpty, "shouldn't attempt to eject a non-ejectable volume")
    }

    func testPinningElsewhereAddsAPinnedSection() async {
        let pins = makeIsolatedPinnedLocationsStore()
        let viewModel = makeViewModel(pins: pins)
        let folder = URL(fileURLWithPath: "/Users/test/Projects")

        pins.toggle(folder)
        // A change made elsewhere arrives on the next run-loop turn.
        for _ in 0..<20 where section("pinned", in: viewModel) == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(section("pinned", in: viewModel)?.destinations.map(\.url), [folder])
        XCTAssertEqual(section("pinned", in: viewModel)?.destinations.first?.kind, .pinned)
    }

    func testUnpinRemovesThePinnedSection() {
        let pins = makeIsolatedPinnedLocationsStore()
        let folder = URL(fileURLWithPath: "/Users/test/Projects")
        pins.toggle(folder)
        let viewModel = makeViewModel(pins: pins)
        let destination = try! XCTUnwrap(section("pinned", in: viewModel)?.destinations.first)

        viewModel.unpin(destination)

        XCTAssertNil(section("pinned", in: viewModel))
        XCTAssertFalse(pins.isPinned(folder))
    }

    func testPinnedLocationsPersistAcrossStores() {
        let service = PinnedLocationsService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let folder = URL(fileURLWithPath: "/Users/test/Projects")
        PinnedLocationsStore(service: service).toggle(folder)

        XCTAssertTrue(PinnedLocationsStore(service: service).isPinned(folder))
    }

    func testTrashAppearsInSpecialSection() {
        let trashURL = URL(fileURLWithPath: "/Users/test/.Trash")
        let viewModel = makeViewModel(trashURL: trashURL)

        XCTAssertEqual(section("special", in: viewModel)?.destinations.map(\.url), [trashURL])
        XCTAssertEqual(section("special", in: viewModel)?.destinations.first?.kind, .trash)
    }

    func testCloudLocationsGetFriendlyNamesSortedByName() {
        let viewModel = makeViewModel(cloudStorageLocations: [
            URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Nextcloud-a8f499f1@nextcloud.example.com"),
            URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs"),
            URL(fileURLWithPath: "/Users/test/Library/CloudStorage/SomeProvider"),
        ])

        XCTAssertEqual(section("cloud", in: viewModel)?.destinations.map(\.name), ["iCloud Drive", "Nextcloud", "SomeProvider"])
    }

    func testHierarchyCandidatesMirrorFolderDestinations() {
        let viewModel = makeViewModel(trashURL: URL(fileURLWithPath: "/Users/test/.Trash"))

        // Every destination but Recents and Shared, which aren't folders.
        XCTAssertEqual(viewModel.hierarchyCandidates.map(\.url), viewModel.allDestinations.filter { !$0.kind.isVirtual }.map(\.url))
        XCTAssertFalse(viewModel.hierarchyCandidates.contains { $0.url.scheme == VirtualLocation.scheme })
    }
}
