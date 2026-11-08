import SwiftUI

/// First-launch explainer shown when the app doesn't have Full Disk
/// Access yet. See SPEC.md §3 for why this is required instead of
/// App Sandbox + security-scoped bookmarks.
struct FullDiskAccessView: View {
    let onOpenSettings: () -> Void
    let onContinueAnyway: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("OneRoot Needs Full Disk Access")
                .font(.title2)
                .bold()

            Text("""
                OneRoot browses your whole filesystem, including folders macOS \
                normally hides from apps — other users' home folders, Time \
                Machine backups, and more. To do that, it needs Full Disk Access:

                1. Click "Open System Settings" below.
                2. In Privacy & Security → Full Disk Access, add OneRoot (or turn \
                on its toggle if it's already listed).
                3. Relaunch OneRoot.
                """)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420, alignment: .leading)

            HStack(spacing: 12) {
                Button("Continue Without It") { onContinueAnyway() }
                Button("Open System Settings") { onOpenSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 380)
    }
}

#Preview {
    FullDiskAccessView(onOpenSettings: {}, onContinueAnyway: {})
}
