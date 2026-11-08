import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Recursive, criteria-driven search over a chosen folder or an entire
/// volume — regex/contains/starts-with name matching, extension/size/date
/// filters, and an optional grep-style content search mode. Opened as its
/// own window (`OneRootApp`'s "advancedSearch" scene) so a long search over
/// a whole drive doesn't block browsing in the main window. See
/// `SearchService` for how the walk itself works.
struct AdvancedSearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var selection = Set<SearchResult.ID>()

    var body: some View {
        VStack(spacing: 0) {
            CriteriaFormView(viewModel: viewModel)
            Divider()
            // What's being searched for, at a glance — and the only place
            // to add a Kind, relative-date, or Tag filter.
            FilterChipBar(
                criteria: $viewModel.criteria,
                context: .advancedSearch,
                tagSuggestions: Array(NSWorkspace.shared.fileLabels.dropFirst()),
                onRemove: { viewModel.remove($0) }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            SearchResultsView(results: viewModel.results, mode: viewModel.criteria.mode, selection: $selection)
            Divider()
            StatusFooterView(viewModel: viewModel)
        }
        .frame(minWidth: 700, minHeight: 480)
        // Search Subfolders: a folder's filter, waiting for this window
        // (just opened, or already open).
        .onChange(of: SearchHandoffCenter.shared.pending) { _, pending in
            if pending != nil { viewModel.takeHandoff(from: .shared) }
        }
    }
}

private struct CriteriaFormView: View {
    @Bindable var viewModel: SearchViewModel
    private var workspaces = WorkspaceStore.shared
    @State private var showingChooseFolder = false
    @State private var savedQueries: [SavedSearchQuery] = []
    @State private var showingSaveQuerySheet = false
    @State private var showingTerminalCommandSheet = false

    private static let contentPatternModes: [SearchPatternMode] = [.contains, .regex]
    private let savedQueriesService = SavedSearchQueriesService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu("Saved Queries") {
                    if savedQueries.isEmpty {
                        Text("No saved queries yet")
                    }
                    ForEach(savedQueries) { query in
                        Button(query.name) { load(query) }
                    }
                    if !savedQueries.isEmpty {
                        Divider()
                        Menu("Delete…") {
                            ForEach(savedQueries) { query in
                                Button(query.name) { delete(query) }
                            }
                        }
                    }
                    Divider()
                    Button("Save Current Query…") { showingSaveQuerySheet = true }
                }
                Spacer()
                Button("Show as Terminal Command…") { showingTerminalCommandSheet = true }
                    .disabled(!viewModel.canSearch)
            }
            .onAppear { savedQueries = savedQueriesService.load() }
            .sheet(isPresented: $showingSaveQuerySheet) {
                SaveSearchQuerySheet { name in
                    savedQueries = savedQueriesService.upsert(SavedSearchQuery(name: name, criteria: viewModel.criteria))
                }
            }
            .sheet(isPresented: $showingTerminalCommandSheet) {
                TerminalCommandSheet(command: SearchCommandLineBuilder().command(for: viewModel.criteria))
            }

            Picker("", selection: $viewModel.criteria.mode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: viewModel.criteria.mode) { _, newMode in
                if newMode == .contents, !Self.contentPatternModes.contains(viewModel.criteria.patternMode) {
                    viewModel.criteria.patternMode = .contains
                }
            }

            // Only meaningful for Name & Metadata mode — a content search
            // only ever looks inside files, so folders are already excluded
            // there regardless of this setting.
            if viewModel.criteria.mode == .nameAndMetadata {
                HStack {
                    Text("Show:")
                    Picker("", selection: $viewModel.criteria.itemType) {
                        ForEach(SearchItemType.allCases, id: \.self) { itemType in
                            Text(itemType.title).tag(itemType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    Spacer()
                }
            }

            HStack {
                Text("Search in:")
                Text(searchInDescription)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                    .help(viewModel.criteria.searchRoots.map(\.path).joined(separator: "\n"))
                Spacer()
                if !workspaces.workspaces.isEmpty {
                    Menu("Workspace") {
                        ForEach(workspaces.workspaces.filter { !$0.folders.isEmpty }) { workspace in
                            Button(workspace.name) { useWorkspace(workspace) }
                        }
                    }
                    .fixedSize()
                    .help("Search every folder of a Workspace at once")
                }
                Button("Choose…") { showingChooseFolder = true }
                Button("Entire Volume") { useVolumeRoot() }
            }
            .sheet(isPresented: $showingChooseFolder) {
                FileChooserView(startingAt: viewModel.criteria.root) { url in
                    useSingleRoot(url)
                }
            }

            HStack {
                TextField(viewModel.criteria.mode == .contents ? "Text to find" : "Name", text: $viewModel.criteria.pattern)
                    .onSubmit { if viewModel.canSearch { viewModel.start() } }
                Picker("", selection: $viewModel.criteria.patternMode) {
                    ForEach(viewModel.criteria.mode == .contents ? Self.contentPatternModes : SearchPatternMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                if viewModel.criteria.patternMode == .regex {
                    Menu("Suggestions") {
                        ForEach(RegexSuggestion.all) { suggestion in
                            Button(suggestion.name) { viewModel.criteria.pattern = suggestion.pattern }
                        }
                    }
                    .fixedSize()
                }
                Toggle("Case Sensitive", isOn: $viewModel.criteria.caseSensitive)
            }

            HStack {
                TextField("Extensions (e.g. pdf, docx)", text: extensionsBinding)
                Toggle("Include Hidden Files", isOn: $viewModel.criteria.includeHidden)
                Toggle("Include Cloud Storage", isOn: $viewModel.criteria.includeCloudStorage)
                    .help("Also searches iCloud Drive, Nextcloud, Google Drive, and the other cloud folders inside the search location. They live in the hidden Library folder, so a search of your home folder or whole drive skips them otherwise. A content search never opens files that aren't downloaded yet, so it can't make your Mac download them. Can be slower, since cloud folders may need listing from the server.")
                Toggle("Use Spotlight Index", isOn: $viewModel.useSpotlightIndex)
                    .disabled(viewModel.criteria.mode != .nameAndMetadata)
                    .help("Shows matches from Spotlight's index right away — near-instant, even across a whole drive — then keeps scanning every folder to add anything Spotlight missed. Doesn't apply to regex patterns, hidden files, or locations Spotlight doesn't index; those just get the full scan.")
            }

            HStack(spacing: 16) {
                sizeField("Min Size (MB)", value: sizeBinding(\.minSizeBytes))
                sizeField("Max Size (MB)", value: sizeBinding(\.maxSizeBytes))
                dateFilter("Modified After", date: $viewModel.criteria.modifiedAfter)
                dateFilter("Modified Before", date: $viewModel.criteria.modifiedBefore)
                Spacer()
            }

            HStack {
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel") { viewModel.cancel() }
                } else {
                    Button("Search") { viewModel.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSearch)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(12)
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { viewModel.criteria.extensions.joined(separator: ", ") },
            set: { newValue in
                viewModel.criteria.extensions = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<SearchCriteria, Int64?>) -> Binding<String> {
        Binding(
            get: {
                guard let bytes = viewModel.criteria[keyPath: keyPath] else { return "" }
                return String(format: "%.0f", Double(bytes) / 1_000_000)
            },
            set: { newValue in
                guard let megabytes = Double(newValue), megabytes > 0 else {
                    viewModel.criteria[keyPath: keyPath] = nil
                    return
                }
                viewModel.criteria[keyPath: keyPath] = Int64(megabytes * 1_000_000)
            }
        )
    }

    private func sizeField(_ title: String, value: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            TextField("", text: value)
                .frame(width: 50)
        }
    }

    private func dateFilter(_ title: String, date: Binding<Date?>) -> some View {
        HStack(spacing: 4) {
            Toggle(title, isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { isOn in date.wrappedValue = isOn ? Date() : nil }
            ))
            if date.wrappedValue != nil {
                DatePicker(
                    "",
                    selection: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    /// Finds the mounted volume containing the current root by longest
    /// matching path prefix — handles nested volumes (e.g. an APFS
    /// container's boot volume vs its Data volume) correctly.
    private func useVolumeRoot() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let path = viewModel.criteria.root.path
        guard let match = volumes.filter({ path.hasPrefix($0.path) }).max(by: { $0.path.count < $1.path.count }) else { return }
        useSingleRoot(match)
    }

    /// "~/Documents", or "Workspace “Phoenix” (3 folders)".
    private var searchInDescription: String {
        let roots = viewModel.criteria.searchRoots
        if roots.count > 1 {
            let name = viewModel.criteria.workspaceName.map { "Workspace \u{201C}\($0)\u{201D}" } ?? "\(roots.count) folders"
            return viewModel.criteria.workspaceName == nil ? name : "\(name) (\(roots.count) folders)"
        }
        return viewModel.criteria.root.path
    }

    private func useWorkspace(_ workspace: Workspace) {
        guard let first = workspace.folders.first else { return }
        viewModel.criteria.root = first
        viewModel.criteria.additionalRoots = Array(workspace.folders.dropFirst())
        viewModel.criteria.workspaceName = workspace.name
    }

    private func useSingleRoot(_ url: URL) {
        viewModel.criteria.root = url
        viewModel.criteria.additionalRoots = []
        viewModel.criteria.workspaceName = nil
    }

    private func load(_ query: SavedSearchQuery) {
        viewModel.criteria = query.criteria
    }

    private func delete(_ query: SavedSearchQuery) {
        savedQueries = savedQueriesService.remove(id: query.id)
    }
}

/// Names and saves the current criteria as a `SavedSearchQuery`.
private struct SaveSearchQuerySheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (String) -> Void

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Query")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// Shows the approximate `find`/`grep` equivalent of the current criteria
/// (see `SearchCommandLineBuilder`), with a one-click copy — for someone
/// who wants to run the same search from Terminal, or script it.
private struct TerminalCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    let command: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminal Command")
                .font(.headline)
            Text("An approximate equivalent — regex flavor, and size/date rounding, differ slightly from how Advanced Search itself matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button(didCopy ? "Copied" : "Copy") { copy() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        didCopy = true
    }
}

private struct StatusFooterView: View {
    @Bindable var viewModel: SearchViewModel

    var body: some View {
        HStack {
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(viewModel.results.count) match\(viewModel.results.count == 1 ? "" : "es")")
                .foregroundStyle(.secondary)
            Menu("Export…") {
                ForEach(SearchResultExportFormat.allCases, id: \.self) { format in
                    Button(format.title) { export(format) }
                }
            }
            .fixedSize()
            .disabled(viewModel.results.isEmpty)
            HelpButton(topic: .advancedSearch, compact: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 24)
    }

    /// A plain `NSSavePanel`, not `FileChooserView` — that one's built for
    /// picking an existing file/folder to open, not naming a new file to
    /// write, and `NSSavePanel` already gives the standard macOS "Save As"
    /// affordances (default name, extension, new-folder) for free.
    private func export(_ format: SearchResultExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Search Results.\(format.fileExtension)"
        if let contentType = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let content = SearchResultExportService().export(viewModel.results, mode: viewModel.criteria.mode, format: format)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var statusText: String {
        let scanned = "\(viewModel.foldersScanned) folders, \(viewModel.filesScanned) files"
        var text: String
        switch viewModel.engine {
        case .spotlightIndex:
            guard let indexed = viewModel.indexMatchCount else {
                return "Searching the Spotlight index…"
            }
            text = "Spotlight found \(indexed) instantly · full scan: \(scanned)"
            text += viewModel.isSearching
                ? " — checking for anything Spotlight missed…"
                : " — \(viewModel.results.count - indexed) more found"
            return text
        case .fullScan(let reason?):
            text = "Full scan (\(reason)): \(scanned)"
        case .fullScan(nil), nil:
            text = "Scanned \(scanned)"
        }
        if viewModel.filesSkipped > 0 {
            text += " (\(viewModel.filesSkipped) skipped)"
        }
        if viewModel.notDownloaded > 0 {
            text += " (\(viewModel.notDownloaded) cloud files not downloaded, left alone)"
        }
        if viewModel.isSearching {
            text += " — searching…"
        }
        return text
    }
}
