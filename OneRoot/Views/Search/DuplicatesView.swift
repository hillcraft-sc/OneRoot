import AppKit
import SwiftUI

/// File ▸ Find Duplicates… (and More ▸ Find Duplicates in the Context
/// Bar): identical files in the current folder — both folders with Dual
/// Pane on — subfolders included. Mark the copies to throw away and move
/// them to the Trash; one of each group always stays.
struct DuplicatesView: View {
    @State private var viewModel: DuplicatesViewModel

    @MainActor
    init(viewModel: DuplicatesViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? DuplicatesViewModel())
    }
    private var handoff = DuplicatesHandoffCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            content
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear(perform: takeHandoff)
        .onChange(of: handoff.pending) { _, pending in
            if pending != nil { takeHandoff() }
        }
        .onDisappear { viewModel.cancel() }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func takeHandoff() {
        guard let roots = handoff.take(), !roots.isEmpty else { return }
        viewModel.start(roots)
    }

    private var rootNames: String {
        viewModel.roots.map { "\u{201C}\(FileManager.default.displayName(atPath: $0.path))\u{201D}" }.joined(separator: " and ")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.roots.isEmpty ? "Find Duplicates" : "Duplicates in \(rootNames)")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch viewModel.state {
            case .running:
                ProgressView().controlSize(.small)
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
            default:
                if !viewModel.roots.isEmpty {
                    Button("Scan Again") { viewModel.start(viewModel.roots) }
                }
            }
        }
    }

    private var summary: String {
        switch viewModel.state {
        case .idle:
            return viewModel.roots.isEmpty
                ? "Choose File \u{25B8} Find Duplicates\u{2026} in a OneRoot window to look in its folder."
                : "Stopped."
        case .running(.scanning(let files)):
            return "Looking at \(files.formatted()) files\u{2026}"
        case .running(.comparing(let done, let total)):
            return "Comparing files of the same size: \(done.formatted()) of \(total.formatted())\u{2026}"
        case .failed(let message):
            return message
        case .done:
            guard !viewModel.groups.isEmpty else { return "No duplicates found. Subfolders were included; empty files and app contents aren\u{2019}t checked." }
            let count = viewModel.groups.count
            return "\(count.formatted()) \(count == 1 ? "set" : "sets") of identical files \u{00B7} \(bytes(viewModel.reclaimable)) could be freed"
        }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if viewModel.groups.isEmpty {
            Spacer(minLength: 0).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            row(file, in: group)
                        }
                    } header: {
                        Text("\(group.files.count) copies \u{00B7} \(bytes(group.size)) each")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func row(_ file: DuplicateFile, in group: DuplicateGroup) -> some View {
        let isMarked = viewModel.isMarked(file)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { isMarked }, set: { _ in viewModel.toggle(file, in: group) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!viewModel.canMark(file, in: group))
                .help(viewModel.canMark(file, in: group) ? "Move to the Trash" : "One copy always stays")
                .accessibilityLabel("Move \(file.url.lastPathComponent) to the Trash")
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .strikethrough(isMarked)
                    .foregroundStyle(isMarked ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(location(of: file.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let modified = file.modified {
                Text(modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(file.url) }
            Button("Show in OneRoot") {
                NotificationCenter.default.post(name: .revealInOneRoot, object: RevealInOneRootRequest(url: file.url.deletingLastPathComponent(), openInNewTab: false))
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
        }
    }

    /// The file's folder, relative to the searched folder it's in
    /// ("Photos Export/Backup"), or its full path with ~ for home.
    private func location(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        for root in viewModel.roots {
            let rootPath = root.resolvingSymlinksInPath().path
            if folder == rootPath { return root.lastPathComponent }
            if folder.hasPrefix(rootPath + "/") {
                return root.lastPathComponent + folder.dropFirst(rootPath.count)
            }
        }
        return folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HelpButton(topic: .fileOperations)
            if !viewModel.groups.isEmpty {
                Button("Mark All but Oldest") { viewModel.markAllButOne(keepingNewest: false) }
                    .help("In every set, keep the oldest copy and mark the rest")
                Button("Mark All but Newest") { viewModel.markAllButOne(keepingNewest: true) }
                    .help("In every set, keep the newest copy and mark the rest")
                Button("Clear") { viewModel.clearMarks() }
                    .disabled(viewModel.marked.isEmpty)
            }
            Spacer()
            Button(role: .destructive) {
                viewModel.trashMarked()
            } label: {
                Text(viewModel.marked.isEmpty ? "Move to Trash" : "Move \(viewModel.marked.count.formatted()) to Trash (\(bytes(viewModel.markedSize)))")
            }
            .disabled(viewModel.marked.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
