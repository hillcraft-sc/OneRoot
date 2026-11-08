import Foundation

/// Quick Actions (resize, convert, combine into PDF, Markdown/HTML…) for
/// the selection. Shared with Linux: the transforms themselves come from
/// `QuickActionServices` (ImageIO and PDFKit on the Mac; GdkPixbuf, qpdf and
/// Cairo on Linux).
extension FileListViewModel {
    /// The Quick Actions that make sense for `nodes` (see
    /// `QuickActionCatalog`) — none in the Trash.
    func quickActionOptions(for nodes: [FileNode]) -> [QuickActionOption] {
        // Items in the Trash are on their way out, not to be worked on.
        guard !(currentDirectory.map(Platform.isTrashFolder) ?? false) else { return [] }
        return QuickActionCatalog().options(for: nodes)
    }

    func promptQuickAction(_ action: QuickAction, for nodes: [FileNode]) {
        guard quickActionOptions(for: nodes).contains(where: { $0.action == action && $0.isAvailable }) else { return }
        pendingQuickAction = PendingQuickAction(action: action, urls: nodes.map(\.url))
    }

    /// Runs what the sheet planned, then shows the new files selected.
    @discardableResult
    func runQuickAction(_ request: QuickActionRequest, plan: QuickActionPlan) -> Task<Void, Never> {
        pendingQuickAction = nil
        return Task {
            let result = await QuickActionRunner(undoCenter: undoCenter).run(request, plan: plan)
            await showNewItems(result.created, error: result.error)
        }
    }
}
