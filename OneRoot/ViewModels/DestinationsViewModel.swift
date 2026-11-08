import Foundation
import Observation

/// The global destination sidebar's model: the places you can start
/// working from — Home, pinned folders, cloud storage, volumes and network
/// shares, and the Trash. Shallow by design; folder-by-folder browsing
/// belongs to the hierarchy pane (`FolderHierarchyViewModel`).
///
/// One per window. Volumes update live from `VolumeService`; pins come from
/// the app-wide `PinnedLocationsStore`.
@MainActor
@Observable
final class DestinationsViewModel {
    private(set) var sections: [DestinationSection] = []
    var errorMessage: String?
    /// False until the first volume list arrives (it's fetched off the main
    /// thread at launch) — until then, roots on volumes can't be checked.
    private(set) var hasLoadedVolumes = false

    private let volumeService: VolumeProviding
    private let pinnedLocations: PinnedLocationsStore
    private let cloudStorageLocations: [URL]
    private let trashURL: URL?
    private let homeURL: URL
    private let applicationsURL: URL?
    private let virtualLocations: [VirtualLocation]
    private let userFolders: [URL]
    private var volumesByURL: [URL: VolumeInfo] = [:]
    @ObservationIgnored private var volumeMonitor: AnyObject?
    private var pinnedWatch: ObservationWatch?

    /// `cloudStorageLocations`/`trashURL` default to empty/nil rather than
    /// discovering real machine state, so tests stay hermetic; production
    /// (`MainWindowView`) passes the real values.
    init(
        volumeService: VolumeProviding = Platform.volumes(),
        pinnedLocations: PinnedLocationsStore? = nil,
        cloudStorageLocations: [URL] = [],
        trashURL: URL? = nil,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsURL: URL? = Platform.applicationsFolder,
        virtualLocations: [VirtualLocation] = Platform.virtualDestinations,
        userFolders: [URL] = []
    ) {
        self.applicationsURL = applicationsURL
        self.virtualLocations = virtualLocations
        self.userFolders = userFolders
        self.volumeService = volumeService
        self.pinnedLocations = pinnedLocations ?? .shared
        self.cloudStorageLocations = cloudStorageLocations
        self.trashURL = trashURL
        self.homeURL = homeURL
        rebuildSections()

        volumeMonitor = volumeService.monitorVolumes { [weak self] volumes in
            self?.applyVolumes(volumes)
        }
        let pinned = self.pinnedLocations
        pinnedWatch = ObservationWatch.watch({ pinned.urls }, emitsInitialValue: false) { [weak self] urls in
            self?.rebuildSections(pinnedURLs: urls)
        }
    }

    var allDestinations: [Destination] { sections.flatMap(\.destinations) }

    /// Everything the hierarchy can be rooted at, for `HierarchyRootResolver`.
    var hierarchyCandidates: [HierarchyRoot] { allDestinations.filter { !$0.kind.isVirtual }.map(\.hierarchyRoot) }

    var ejectableURLs: Set<URL> {
        Set(allDestinations.filter(\.isEjectable).map(\.url))
    }

    func applyVolumes(_ volumes: [VolumeInfo]) {
        volumesByURL = Dictionary(uniqueKeysWithValues: volumes.map { ($0.url, $0) })
        rebuildSections()
        if !hasLoadedVolumes { hasLoadedVolumes = true }
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedLocations.isPinned(url)
    }

    func unpin(_ destination: Destination) {
        pinnedLocations.unpin(destination.url)
        rebuildSections() // now, not a turn later via the watch
    }

    /// Ejects off the main actor: unmounting can wait on a busy drive or a
    /// share that stopped answering, and the window must stay alive meanwhile.
    /// Returns the task so tests can wait for it.
    @discardableResult
    func eject(_ destination: Destination) -> Task<Void, Never> {
        guard let volume = volumesByURL[destination.url], isEjectable(volume) else { return Task {} }
        nonisolated(unsafe) let service = volumeService
        return Task { [weak self] in
            let (ejected, detail) = await Task.detached(priority: .userInitiated) { () -> (Bool, String?) in
                let ok = service.eject(volume)
                return (ok, ok ? nil : service.lastEjectFailure())
            }.value
            if !ejected {
                var message = "Couldn't eject \"\(volume.name)\". Make sure nothing is using it, then try again."
                if let detail, !detail.isEmpty { message += " (\(detail))" }
                self?.errorMessage = message
            }
        }
    }

    /// Ejects the volume at `url` if it's one — ⌘J from the main menu acts
    /// on whatever destination the active tab is rooted at.
    @discardableResult
    func eject(at url: URL) -> Task<Void, Never> {
        guard let destination = allDestinations.first(where: { $0.url == url }) else { return Task {} }
        return eject(destination)
    }

    /// Physical/removable media report `isEjectable` themselves; network
    /// shares (SMB/AFP/NFS) never do, but unmounting one is the same
    /// `NSWorkspace.unmountAndEjectDevice` call Finder uses — so they count.
    private func isEjectable(_ volume: VolumeInfo) -> Bool {
        volume.isEjectable || !volume.isLocal
    }

    /// Fixed section order: Home (untitled), Pinned and Cloud (each only
    /// once there's something in them), Locations, Special. Home appears
    /// once, at the top — not again under Locations. Under it: the
    /// platform's lists (Recents and Shared on the Mac) and its user
    /// folders (Desktop, Documents, … on Linux).
    private func rebuildSections(pinnedURLs: [URL]? = nil) {
        let home = Destination(url: homeURL, name: homeURL.lastPathComponent, kind: .home)

        let pinned = (pinnedURLs ?? pinnedLocations.urls).map {
            Destination(url: $0, name: $0.lastPathComponent, kind: .pinned)
        }

        let cloud = cloudStorageLocations
            .map { Destination(url: $0, name: $0.friendlyFolderName, kind: .cloud) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var locations: [Destination] = []
        if let boot = volumesByURL.values.first(where: { $0.url.path == "/" }) {
            locations.append(Destination(url: boot.url, name: boot.name, kind: .bootVolume))
        }
        if let applicationsURL {
            locations.append(Destination(url: applicationsURL, name: "Applications", kind: .applications))
        }
        locations += volumesByURL.values
            .filter { $0.url.path != "/" }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Destination(url: $0.url, name: $0.name, kind: $0.isLocal ? .volume : .networkVolume, isEjectable: isEjectable($0)) }

        let lists = virtualLocations.map { location in
            Destination(url: location.url, name: location.title, kind: location == .recents ? .recents : .shared)
        }
        let folders = userFolders.map { Destination(url: $0, name: $0.lastPathComponent, kind: .folder) }
        var newSections = [DestinationSection(id: "home", title: "", destinations: [home] + lists + folders)]
        if !pinned.isEmpty {
            newSections.append(DestinationSection(id: "pinned", title: "Pinned", destinations: pinned))
        }
        if !cloud.isEmpty {
            newSections.append(DestinationSection(id: "cloud", title: "Cloud", destinations: cloud))
        }
        newSections.append(DestinationSection(id: "locations", title: "Locations", destinations: locations))
        if let trashURL {
            newSections.append(DestinationSection(id: "special", title: "Special", destinations: [
                Destination(url: trashURL, name: "Trash", kind: .trash),
            ]))
        }

        // Only publish real changes — the volumes publisher re-emits on
        // every mount anywhere, mostly producing an identical list.
        if newSections != sections {
            sections = newSections
        }
    }
}
