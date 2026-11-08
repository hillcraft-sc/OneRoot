import AppKit
import SwiftUI

/// The full navigation history (`NavigationHistoryStore`) — the Go menu's
/// "Recent Locations" submenu only shows the most recent handful; this window
/// (opened by "Show All History…") lists everything, up to the cap set in
/// Settings, with a filter box.
///
/// Double-click or select-and-Open navigates the frontmost main window's
/// active tab there, reusing the same `.revealInOneRoot` notification the
/// Advanced Search window uses.
struct HistoryView: View {
    @Environment(\.appTheme) private var theme
    private var history = NavigationHistoryStore.shared
    @State private var query = ""
    @State private var selection: URL?

    private var filtered: [URL] {
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text(history.entries.isEmpty ? "No history yet." : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered, id: \.self, selection: $selection) { url in
                    row(for: url)
                        .tag(url)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(url) }
                }
            }

            Divider()

            HStack {
                Text("\(history.entries.count) location\(history.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open") { if let selection { open(selection) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
                Button("Clear History") { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
            .padding(8)
        }
        .frame(minWidth: 460, minHeight: 340)
        .navigationTitle("History")
        .background {
            // Guarantees ⌘W closes this window. The File menu's "Close Tab"
            // command (`AppCommands.FileMenuCommands`) binds ⌘W app-wide and
            // was shadowing AppKit's standard "Close Window" here.
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        }
    }

    private func row(for url: URL) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: ThemedIcons.icon(for: url, isFolder: Self.isPlainFolder(url), theme: theme))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private func open(_ url: URL) {
        NotificationCenter.default.post(
            name: .revealInOneRoot,
            object: RevealInOneRootRequest(url: url, openInNewTab: false)
        )
    }

    /// A folder to show in the theme's color — not a drive, share, or app.
    private static func isPlainFolder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isVolumeKey, .isPackageKey]) else { return true }
        return values.isDirectory == true && values.isVolume != true && values.isPackage != true
    }
}
