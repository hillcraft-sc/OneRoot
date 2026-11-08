import Foundation
import Observation

/// Whether to show hidden (dot-prefixed) files is a single app-wide
/// preference, same reasoning as `ColumnPreferencesStore`: `.shared` is
/// observed by every open tab/window's `FileListViewModel`, so toggling
/// it anywhere refreshes every file list immediately.
@MainActor
@Observable
final class HiddenFilesPreferenceStore {
    static let shared = HiddenFilesPreferenceStore()

    private(set) var showHiddenFiles: Bool

    private let service: HiddenFilesPreferenceService

    init(service: HiddenFilesPreferenceService = HiddenFilesPreferenceService()) {
        self.service = service
        self.showHiddenFiles = service.load()
    }

    func toggle() {
        showHiddenFiles.toggle()
        service.save(showHiddenFiles)
    }
}
