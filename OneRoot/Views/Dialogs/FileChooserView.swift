import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// OneRoot's own file/folder picker — used everywhere the app would
/// otherwise open `NSOpenPanel` (Advanced Search's starting folder, Restore
/// destinations, archive folders, the Terminal and editor app pickers, SSH
/// keys, Workspace folders), so a Finder replacement doesn't pop open
/// Finder's picker. Laid out like the main window: Back/Forward/Up and an
/// editable path on top, shortcuts and a folder tree on the left, the
/// folder's contents on the right. The tree is its own small SwiftUI list,
/// not the main window's `NSOutlineView`, which is tied to pinning, Trash,
/// rename, and drag and drop. The work lives in `FileChooserViewModel`.
struct FileChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FileChooserViewModel
    @FocusState private var isPathFocused: Bool

    let message: String?
    let chooseButtonTitle: String
    let onChoose: ([URL]) -> Void

    /// Picks one item.
    init(
        startingAt url: URL,
        canChooseFiles: Bool = false,
        canChooseDirectories: Bool = true,
        allowedContentTypes: [UTType] = [],
        showsHiddenFiles: Bool = false,
        message: String? = nil,
        chooseButtonTitle: String = "Choose",
        onChoose: @escaping (URL) -> Void
    ) {
        self.init(
            startingAt: url,
            options: .init(canChooseFiles: canChooseFiles, canChooseDirectories: canChooseDirectories, allowsFile: Self.filter(allowedContentTypes)),
            showsHiddenFiles: showsHiddenFiles,
            message: message,
            chooseButtonTitle: chooseButtonTitle,
            onChooseMultiple: { urls in urls.first.map(onChoose) }
        )
    }

    /// Files of one of `types` (any file when empty), by their content type.
    nonisolated static func filter(_ types: [UTType]) -> (@Sendable (URL) -> Bool)? {
        guard !types.isEmpty else { return nil }
        return { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
            return types.contains { type.conforms(to: $0) }
        }
    }

    /// Picks one or more folders (⌘-click, ⇧-click) — Workspace ▸ Add.
    init(
        multipleFoldersStartingAt url: URL,
        message: String? = nil,
        chooseButtonTitle: String = "Choose",
        onChoose: @escaping ([URL]) -> Void
    ) {
        self.init(
            startingAt: url,
            options: .init(allowsMultipleSelection: true),
            showsHiddenFiles: false,
            message: message,
            chooseButtonTitle: chooseButtonTitle,
            onChooseMultiple: onChoose
        )
    }

    private init(
        startingAt url: URL,
        options: FileChooserViewModel.Options,
        showsHiddenFiles: Bool,
        message: String?,
        chooseButtonTitle: String,
        onChooseMultiple: @escaping ([URL]) -> Void
    ) {
        // Hidden items start as the main window shows them, or on when the
        // caller needs them (SSH keys live in ~/.ssh).
        let showsHidden = showsHiddenFiles || HiddenFilesPreferenceStore.shared.showHiddenFiles
        _viewModel = State(initialValue: FileChooserViewModel(startingAt: url, options: options, showsHidden: showsHidden))
        self.message = message
        self.chooseButtonTitle = chooseButtonTitle
        self.onChoose = onChooseMultiple
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Places, then the folder tree, then the folder's contents — the
            // main window's destinations, hierarchy, and list.
            HSplitView {
                FileChooserPlaces(viewModel: viewModel)
                    .frame(minWidth: 140, idealWidth: 170, maxWidth: 200)
                FileChooserTree(viewModel: viewModel)
                    .frame(minWidth: 170, idealWidth: 210, maxWidth: 280)
                FileChooserContents(viewModel: viewModel, onChoose: choose)
                    .frame(minWidth: 360)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 900, maxWidth: 1500, minHeight: 440, idealHeight: 560, maxHeight: 1000)
        .task { await viewModel.start() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message {
                Text(message)
                    .font(.callout)
            }
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Button { Task { await viewModel.goBack() } } label: { Image(systemName: "chevron.left") }
                        .disabled(!viewModel.canGoBack)
                        .help("Back")
                        .accessibilityLabel("Back")
                    Button { Task { await viewModel.goForward() } } label: { Image(systemName: "chevron.right") }
                        .disabled(!viewModel.canGoForward)
                        .help("Forward")
                        .accessibilityLabel("Forward")
                    Button { Task { await viewModel.goUp() } } label: { Image(systemName: "arrow.up") }
                        .disabled(!viewModel.canGoUp)
                        .help("Up One Level")
                        .accessibilityLabel("Up One Level")
                }
                .buttonStyle(BarButtonStyle())
                .fontWeight(.medium)
                pathField
            }
            if let pathError = viewModel.pathError {
                Text(pathError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .zIndex(1) // the suggestions hang over the panes below
    }

    /// Shows where you are; type or paste a path and press Return to go
    /// there. Matching subfolders appear below as you type — Tab takes
    /// the first, a click takes any.
    private var pathField: some View {
        TextField("Path", text: $viewModel.pathText)
            .textFieldStyle(.roundedBorder)
            .focused($isPathFocused)
            .accessibilityLabel("Path")
            .help("Type or paste a path, then press Return")
            .onSubmit { Task { await viewModel.submitPath() } }
            .onChange(of: viewModel.pathText) { _, _ in
                guard isPathFocused else { return }
                Task { await viewModel.updateSuggestions() }
            }
            .onChange(of: isPathFocused) { _, focused in
                if !focused { viewModel.cancelPathEditing() }
            }
            .onKeyPress(.tab) {
                guard let first = viewModel.suggestions.first else { return .ignored }
                Task { await viewModel.acceptSuggestion(first) }
                return .handled
            }
            .onExitCommand { viewModel.cancelPathEditing() }
            .overlay(alignment: .topLeading) {
                if isPathFocused, !viewModel.suggestions.isEmpty {
                    suggestionList
                        .offset(y: 26)
                }
            }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.suggestions, id: \.self) { name in
                Button {
                    Task { await viewModel.acceptSuggestion(name) }
                } label: {
                    Label(name, systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 240, alignment: .leading)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .shadow(radius: 6, y: 2)
        .accessibilityLabel("Folder suggestions")
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle("Show Hidden Files", isOn: Binding(
                get: { viewModel.showsHidden },
                set: { shows in Task { await viewModel.setShowsHidden(shows) } }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            if viewModel.options.allowsMultipleSelection, viewModel.selection.count > 1 {
                Text("\(viewModel.chosenURLs.count) folders selected")
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(chooseButtonTitle) { choose(viewModel.chosenURLs) }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canChoose)
        }
        .padding(10)
    }

    private func choose(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        onChoose(urls)
        dismiss()
    }
}

/// Left: Home, Pinned, Cloud, and Locations. Choosing one goes there and
/// roots the tree at it.
private struct FileChooserPlaces: View {
    @Bindable var viewModel: FileChooserViewModel

    var body: some View {
        List(selection: Binding<URL?>(
            get: { viewModel.treeRoot.url },
            set: { url in
                // A tick later: never navigate from inside a view update.
                DispatchQueue.main.async {
                    guard let destination = viewModel.shortcutSections.flatMap(\.destinations).first(where: { $0.url == url }) else { return }
                    Task { await viewModel.openShortcut(destination) }
                }
            }
        )) {
            ForEach(viewModel.shortcutSections) { section in
                Section(section.title) {
                    ForEach(section.destinations) { destination in
                        Label(destination.name, systemImage: destination.kind.systemImage)
                            .lineLimit(1)
                            .tag(destination.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Places")
    }
}

/// Middle: the folders of the current place, opened down to where you are.
private struct FileChooserTree: View {
    @Bindable var viewModel: FileChooserViewModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: Binding<URL?>(
                get: { viewModel.currentDirectory },
                set: { url in
                    guard let url else { return }
                    DispatchQueue.main.async { Task { await viewModel.navigate(to: url) } }
                }
            )) {
                ForEach(viewModel.treeRows) { row in
                    treeRow(row)
                        .tag(row.url)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Folders")
            // Keeps where you are in view as the tree opens down to it.
            .onChange(of: viewModel.treeRows) { _, _ in
                proxy.scrollTo(viewModel.currentDirectory, anchor: .center)
            }
        }
    }

    private func treeRow(_ row: FileChooserViewModel.TreeRow) -> some View {
        HStack(spacing: 4) {
            Group {
                if row.depth > 0, viewModel.mayHaveSubfolders(row.url) {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        // Beats the row's own selection click.
                        .highPriorityGesture(TapGesture().onEnded {
                            Task { await viewModel.toggleExpanded(row.url) }
                        })
                        .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
                } else if row.depth > 0 {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            Image(nsImage: ThemedIcons.icon(for: row.url, isFolder: true, theme: theme))
                .resizable()
                .frame(width: 16, height: 16)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, CGFloat(max(row.depth - 1, 0)) * 14)
        .accessibilityElement(children: .combine)
    }
}

/// Right side: what's in the current folder. Double-click or Return opens
/// a folder, or chooses anything else that can be chosen.
private struct FileChooserContents: View {
    @Bindable var viewModel: FileChooserViewModel
    let onChoose: ([URL]) -> Void
    @Environment(\.appTheme) private var theme

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        Table(viewModel.entries, selection: Binding(
            get: { viewModel.selection },
            set: { viewModel.setSelection($0) }
        )) {
            TableColumn("Name") { node in
                HStack(spacing: 6) {
                    Image(nsImage: ThemedIcons.icon(for: node.url, isFolder: FileChooserViewModel.isBrowsableFolder(node), theme: theme))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // Things that can't be chosen here (files, when picking a
                // folder) are dimmed but still there to see.
                .opacity(viewModel.isSelectable(node) || FileChooserViewModel.isBrowsableFolder(node) ? 1 : 0.45)
            }
            .width(min: 140, ideal: 180)
            TableColumn("Date Modified") { node in
                Text(node.modificationDate.map(Self.dateFormatter.string(from:)) ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Kind") { node in
                Text(node.kind ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: URL.self) { _ in
            EmptyView()
        } primaryAction: { urls in
            guard urls.count == 1, let url = urls.first else { return }
            Task {
                if let chosen = await viewModel.open(url) { onChoose(chosen) }
            }
        }
        .overlay { stateOverlay }
        .accessibilityLabel("Folder contents")
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if let error = viewModel.listingError {
            ContentUnavailableView("Can\u{2019}t Open This Folder", systemImage: "lock", description: Text(error))
        } else if viewModel.isLoading, viewModel.entries.isEmpty {
            ProgressView()
        } else if viewModel.entries.isEmpty {
            Text(viewModel.options.canChooseFiles ? "Empty folder" : "No folders here")
                .foregroundStyle(.secondary)
        }
    }
}
