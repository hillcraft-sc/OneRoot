import Foundation
import Observation

/// The user's Workspaces, shared by every window — the sidebar lists them,
/// the hierarchy shows the active one's folders, the Inspector adds to
/// them. Same app-wide pattern as `PinnedLocationsStore`.
@MainActor
@Observable
final class WorkspaceStore {
    static let shared = WorkspaceStore()

    private(set) var workspaces: [Workspace]

    private let service: WorkspaceService

    init(service: WorkspaceService = WorkspaceService()) {
        self.service = service
        self.workspaces = service.load()
    }

    func workspace(_ id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    /// Adds `workspace`, or replaces the one with its `id`.
    func save(_ workspace: Workspace) {
        var workspace = workspace
        workspace.name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspace.name.isEmpty { workspace.name = uniqueName() }
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
        service.save(workspaces)
    }

    func delete(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        service.save(workspaces)
    }

    func addFolders(_ urls: [URL], to id: UUID) {
        guard let workspace = workspace(id) else { return }
        save(workspace.addingFolders(urls))
    }

    /// A new Workspace holding `folder`, named after it.
    @discardableResult
    func create(with folder: URL) -> Workspace {
        let workspace = Workspace(name: uniqueName(base: folder.lastPathComponent), folders: [folder])
        save(workspace)
        return workspace
    }

    /// "New Workspace", or "New Workspace 2", … if that's taken.
    func uniqueName(base: String = "New Workspace") -> String {
        let taken = Set(workspaces.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
