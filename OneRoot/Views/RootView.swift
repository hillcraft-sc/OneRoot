import SwiftUI

/// Gates `MainWindowView` behind the Full Disk Access check (SPEC.md §3).
/// "Continue Without It" is a per-launch override, not a persisted
/// preference — directory reads under protected locations will still fail
/// per-call (handled and surfaced there), so nagging on every relaunch
/// until access is actually granted is the right default.
struct RootView: View {
    /// Non-`nil` only for the tab-handoff `WindowGroup` (a tab torn off
    /// into its own window — see `OneRootApp`'s `tabHandoffWindowID`
    /// scene); `nil` for every ordinary window (the default `WindowGroup`,
    /// opened at launch or via ⌘N).
    var handoffToken: UUID?

    @StateObject private var ownedFullDiskAccess = OwnedModel(FullDiskAccessViewModel())
    private var fullDiskAccess: FullDiskAccessViewModel { ownedFullDiskAccess.value }
    @State private var continuedAnyway = false
    private var fileOperationProgress = FileOperationProgressCenter.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var floatingWindowIDs: [UUID] {
        fileOperationProgress.showsFloatingWindows
            ? fileOperationProgress.operations.filter(\.opensFloatingWindow).map(\.id)
            : []
    }

    init(handoffToken: UUID? = nil) {
        self.handoffToken = handoffToken
    }

    var body: some View {
        Group {
            if fullDiskAccess.hasAccess || continuedAnyway {
                MainWindowView(handoffToken: handoffToken)
            } else {
                FullDiskAccessView(
                    onOpenSettings: { fullDiskAccess.openSystemSettings() },
                    onContinueAnyway: { continuedAnyway = true }
                )
            }
        }
        .themedWindow(matchesBars: true)
        // Owns the full open/close lifecycle for every progress popup,
        // driven purely by diffing `FileOperationProgressCenter.operations`
        // — deliberately not left to `FileOperationProgressView` to
        // self-dismiss (see that view's comment): `openWindow` involves a
        // real window-server round trip, so a view-side "close myself if
        // my operation is already gone" check could fire before the
        // window ever finished presenting for a fast operation. Harmless
        // if more than one `RootView` reacts to the same app-wide center
        // (⌘N gives this app more than one main window): both
        // `openWindow`/`dismissWindow` are no-ops for an id/value pair
        // that's already in the requested state.
        // No floating window while the front window shows the File
        // Operations card — the card has the same progress; hiding the card
        // brings the windows (back) up.
        .onChange(of: floatingWindowIDs) { previousIDs, currentIDs in
            for id in currentIDs where !previousIDs.contains(id) {
                openWindow(id: OneRootApp.fileOperationProgressWindowID, value: id)
            }
            for id in previousIDs where !currentIDs.contains(id) {
                dismissWindow(id: OneRootApp.fileOperationProgressWindowID, value: id)
            }
        }
    }
}

#Preview {
    RootView()
}
