import SwiftUI

/// The strip above the two panes while Compare Panes is on: progress while
/// comparing, then what differs on each side, Differences Only, and Copy to
/// Right / Copy to Left (each previewed first).
struct PaneComparisonBar: View {
    @Bindable var comparison: PaneComparison

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Compare Panes")
        .sheet(item: $comparison.pendingSync) { plan in
            PaneSyncSheet(plan: plan, sourceName: name(plan.toRight ? comparison.leftURL : comparison.rightURL)) {
                comparison.performSync(plan)
            } onCancel: {
                comparison.pendingSync = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch comparison.state {
        case .comparing(let scanned):
            ProgressView().controlSize(.small)
            Text(scanned > 0 ? "Comparing\u{2026} \(scanned.formatted()) items" : "Comparing\u{2026}")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { comparison.end() }
                .keyboardShortcut(.cancelAction)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Compare Again") { comparison.start() }
            Button("Done") { comparison.end() }
        case .done(let result):
            if result.isIdentical {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("The folders match").fontWeight(.medium)
            } else {
                summary(result, onLeft: true)
                Divider().frame(height: 14)
                summary(result, onLeft: false)
                if result.unreadableCount > 0 {
                    Text("\(result.unreadableCount) unreadable")
                        .foregroundStyle(.orange)
                        .help("Folders that couldn\u{2019}t be read count as different")
                }
            }
            Spacer(minLength: 8)
            if !result.isIdentical {
                Toggle("Differences Only", isOn: $comparison.showsOnlyDifferences)
                    .toggleStyle(.checkbox)
                Button("\u{2190} Copy to Left") { comparison.planSync(toRight: false) }
                    .help("Copy what\u{2019}s newer or missing from \u{201C}\(name(comparison.rightURL))\u{201D} into \u{201C}\(name(comparison.leftURL))\u{201D}")
                Button("Copy to Right \u{2192}") { comparison.planSync(toRight: true) }
                    .help("Copy what\u{2019}s newer or missing from \u{201C}\(name(comparison.leftURL))\u{201D} into \u{201C}\(name(comparison.rightURL))\u{201D}")
            }
            Button {
                comparison.start()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Compare Again")
            .accessibilityLabel("Compare Again")
            Button("Done") { comparison.end() }
        }
    }

    /// "“Photos”: 3 newer · 2 only here · 1 differs" for one side.
    private func summary(_ result: FolderComparison, onLeft: Bool) -> some View {
        let parts: [(ComparisonStatus, Int)] = [.newerHere, .onlyHere, .differs]
            .map { ($0, result.count($0, onLeft: onLeft)) }
            .filter { $0.1 > 0 }
        let folder = name(onLeft ? comparison.leftURL : comparison.rightURL)
        return HStack(spacing: 6) {
            Text("\u{201C}\(folder)\u{201D}:")
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            if parts.isEmpty {
                Text("nothing newer or extra").foregroundStyle(.secondary)
            }
            ForEach(parts, id: \.0) { status, count in
                Text("\(count) \(ComparisonStatusStyle.label(status).lowercased())")
                    .foregroundStyle(Color(nsColor: ComparisonStatusStyle.color(status)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func name(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }
}

/// The preview before Copy to Left/Right: exactly which items will be
/// copied, and what won't.
struct PaneSyncSheet: View {
    let plan: PaneComparison.SyncPlan
    let sourceName: String
    let onCopy: () -> Void
    let onCancel: () -> Void

    private var destinationName: String {
        FileManager.default.displayName(atPath: plan.destination.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.toRight ? "arrow.right.square" : "arrow.left.square")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.items.isEmpty
                         ? "Nothing to copy to \u{201C}\(destinationName)\u{201D}"
                         : "Copy \(plan.items.count == 1 ? "1 item" : "\(plan.items.count) items") from \u{201C}\(sourceName)\u{201D} to \u{201C}\(destinationName)\u{201D}?")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Copies what\u{2019}s newer or missing. Folders are merged, copying only the newer and missing things inside. Nothing is deleted, nothing newer in \u{201C}\(destinationName)\u{201D} is overwritten, and files that are replaced go to the Trash.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !plan.items.isEmpty {
                List(plan.items, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: url.hasDirectoryPath || isFolder(url) ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let status = plan.statuses[url.lastPathComponent] {
                            Text(ComparisonStatusStyle.label(status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(nsColor: ComparisonStatusStyle.color(status)))
                                .help(ComparisonStatusStyle.explanation(status))
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: min(CGFloat(plan.items.count) * 26 + 8, 260))
            }

            if !plan.notCopied.isEmpty {
                Text("Not copied (changed on both sides, or the same date with a different size): \(plan.notCopied.prefix(5).joined(separator: ", "))\(plan.notCopied.count > 5 ? ", and \(plan.notCopied.count - 5) more" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                HelpButton(topic: .dualPane)
                Spacer()
                if plan.items.isEmpty {
                    Button("OK", action: onCancel)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Copy", action: onCopy)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
