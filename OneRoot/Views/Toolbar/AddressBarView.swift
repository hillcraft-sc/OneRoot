import SwiftUI

/// Windows-style address bar. Shows the path as clickable breadcrumbs
/// (`BreadcrumbBarView`) until you click its empty space or press ⇧⌘G —
/// then it's a text field that navigates on Return or Go, and goes back
/// to breadcrumbs on Esc, on navigating, or when you click away. With
/// Settings ▸ General ▸ Address bar set to "Text field" (`AddressBarStyle`)
/// it's always the text field instead, exactly as before breadcrumbs.
///
/// Accepts absolute paths, `~` expansion, and smb://host/share addresses
/// (mounted on the fly via `NetworkShareService`, using any saved Keychain
/// credentials for that host). Invalid input shows inline red text instead
/// of navigating.
///
/// Also autocompletes folder names as you type (Explorer has this, Finder
/// doesn't) — a dropdown of matching subfolder names in whatever directory
/// you're currently typing inside, navigable with ↑/↓, accepted with
/// Return or a click, dismissed with Esc.
struct AddressBarView: View {
    var viewModel: FileListViewModel
    /// Breadcrumbs vs. typing, the typed text, and its error — see
    /// `AddressBarEditor`, which holds the rules for switching between them.
    @State private var editor = AddressBarEditor(alwaysTextField: false, currentPath: "")
    @State private var isConnecting = false
    @FocusState private var isFocused: Bool
    @Environment(\.appTheme) private var theme
    @AppStorage(AddressBarStyle.storageKey) private var style: AddressBarStyle = .breadcrumbs

    @State private var suggestions: [String] = []
    @State private var highlightedSuggestionIndex: Int?
    @State private var suggestionTask: Task<Void, Never>?
    /// Caches the last-listed directory's full (unfiltered) child names,
    /// so most keystrokes just re-filter this in memory instead of
    /// re-touching disk — only the first keystroke into a *new* directory
    /// triggers a real `FileManager` listing.
    @State private var cachedSuggestionDirectory: URL?
    @State private var cachedSuggestionNames: [String] = []

    private let resolver = PathResolver()
    private let networkShareService = NetworkShareService()
    private let fileSystemService = FileSystemService()

    private static let maxSuggestions = 50
    private static let maxDropdownHeight: CGFloat = 280

    var body: some View {
        HStack(spacing: 6) {
            if !editor.isEditing {
                BreadcrumbBarView(
                    segments: viewModel.currentLocationURL.map { BreadcrumbBuilder.segments(for: $0) } ?? [],
                    onNavigate: { viewModel.navigate(to: $0) },
                    onOpenInNewTab: { viewModel.requestOpenInNewTab($0) },
                    onBeginEditing: beginEditing,
                    onCopyPath: {
                        if let folder = viewModel.currentDirectory { viewModel.copyPaths([folder]) }
                    },
                    onDrop: { urls, folder, move in viewModel.handleDrop(urls: urls, into: folder, move: move) }
                )
            } else {
                pathField
            }
        }
        .onAppear {
            editor = AddressBarEditor(alwaysTextField: style == .textField, currentPath: currentPath)
        }
        .onChange(of: style) { _, newStyle in
            editor = AddressBarEditor(alwaysTextField: newStyle == .textField, currentPath: currentPath)
        }
        .onChange(of: viewModel.currentDirectory) { _, _ in
            // Don't clobber what the user is typing.
            editor.currentPathChanged(to: currentPath, isTyping: isFocused)
        }
        // Another tab (or the other side of Dual Pane): anything typed was
        // for the pane that was showing.
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            clearSuggestions()
            isFocused = false
            editor.paneChanged(currentPath: currentPath)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                clearSuggestions()
                // Clicked away: drop whatever was half-typed, like Explorer.
                if !editor.alwaysTextField, !isConnecting { endEditing() }
            }
        }
        .onChange(of: viewModel.addressEditTrigger) { _, _ in
            beginEditing()
        }
    }

    private var pathField: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextField("Path", text: $editor.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .disabled(isConnecting)
                    .onKeyPress(.downArrow) {
                        guard !suggestions.isEmpty else { return .ignored }
                        moveSuggestionHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard !suggestions.isEmpty else { return .ignored }
                        moveSuggestionHighlight(by: -1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if !suggestions.isEmpty {
                            clearSuggestions()
                        } else if !editor.alwaysTextField {
                            endEditing()
                        } else {
                            return .ignored
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        // Key presses arrive during SwiftUI's view update;
                        // navigating from there publishes the view model's
                        // changes mid-update ("Publishing changes from within
                        // view updates"), so act on the next run-loop turn.
                        DispatchQueue.main.async {
                            if let highlightedSuggestionIndex, suggestions.indices.contains(highlightedSuggestionIndex) {
                                acceptSuggestion(suggestions[highlightedSuggestionIndex])
                            } else {
                                navigate()
                            }
                        }
                        return .handled
                    }
                    .onChange(of: editor.text) { _, newValue in
                        editor.textEdited()
                        refreshSuggestions(for: newValue)
                    }

                if isFocused, !suggestions.isEmpty {
                    suggestionList
                        .offset(y: 30)
                }
            }
            .zIndex(1)

            Button(isConnecting ? "Connecting…" : "Go", action: navigate)
                .disabled(isConnecting)

            if let errorMessage = editor.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var currentPath: String { viewModel.currentDirectory?.path ?? "" }

    private func beginEditing() {
        editor.begin(currentPath: currentPath)
        // Focus once the field exists, then select the whole path so
        // typing replaces it — same as clicking Explorer's address bar.
        DispatchQueue.main.async {
            isFocused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    /// Back to breadcrumbs. A no-op in text-field style, which keeps
    /// focus and text the way the address bar always did.
    private func endEditing() {
        guard !editor.alwaysTextField else { return }
        clearSuggestions()
        isFocused = false
        editor.cancel(currentPath: currentPath)
    }

    private var suggestionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index == highlightedSuggestionIndex ? theme.accentColor : Color.clear)
                            .foregroundStyle(index == highlightedSuggestionIndex ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                            .onTapGesture { acceptSuggestion(name) }
                            .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: highlightedSuggestionIndex) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: Self.maxDropdownHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.surfaces?.field.color ?? Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.separatorColor))
        .shadow(radius: 4)
    }

    private func navigate() {
        clearSuggestions()
        switch editor.submit(resolver.resolve(editor.text)) {
        case .navigate(let url):
            viewModel.navigate(to: url)
            finishEditing(at: url)
        case .connect(let url):
            connectToNetworkShare(url)
        case .stay:
            break
        }
    }

    private func finishEditing(at url: URL) {
        if !editor.alwaysTextField {
            clearSuggestions()
            isFocused = false
        }
        editor.finish(currentPath: url.path)
    }

    private func connectToNetworkShare(_ url: URL) {
        isConnecting = true
        Task {
            let credentials = url.host.flatMap { networkShareService.savedCredentials(host: $0) }
            do {
                let mountPoints = try await networkShareService.mount(url: url, credentials: credentials)
                isConnecting = false
                if let mountPoint = mountPoints.first {
                    viewModel.navigate(to: mountPoint)
                    finishEditing(at: mountPoint)
                } else {
                    endEditing()
                }
            } catch {
                isConnecting = false
                editor.connectionFailed(error.localizedDescription)
            }
        }
    }

    // MARK: Autocomplete

    private func refreshSuggestions(for text: String) {
        suggestionTask?.cancel()
        highlightedSuggestionIndex = nil
        // Ignore programmatic text updates (`.onAppear`, syncing to
        // `viewModel.currentDirectory`) — only actual typing should
        // trigger a lookup.
        guard isFocused, let (directory, prefix) = autocompleteSplit(for: text) else {
            suggestions = []
            return
        }
        suggestionTask = Task {
            await loadSuggestions(directory: directory, prefix: prefix)
        }
    }

    /// `PathResolver.splitForAutocomplete` only understands absolute-
    /// looking input (`/…` or `~…`). If the field doesn't look like that
    /// but isn't empty either, treat the whole thing as a plain prefix
    /// to match against whatever folder is currently open — so clearing
    /// the address bar and typing a bare name still autocompletes,
    /// instead of only working when you retype a full absolute path.
    private func autocompleteSplit(for text: String) -> (directory: URL, prefix: String)? {
        if let split = resolver.splitForAutocomplete(text) {
            return split
        }
        guard !text.isEmpty, let currentDirectory = viewModel.currentDirectory else { return nil }
        return (currentDirectory, text)
    }

    private func loadSuggestions(directory: URL, prefix: String) async {
        if directory != cachedSuggestionDirectory {
            let names = await fileSystemService.suggestFolders(in: directory)
            guard !Task.isCancelled else { return }
            cachedSuggestionDirectory = directory
            cachedSuggestionNames = names
        }
        guard !Task.isCancelled else { return }
        let matches = prefix.isEmpty
            ? cachedSuggestionNames
            : cachedSuggestionNames.filter { $0.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil }
        suggestions = Array(matches.prefix(Self.maxSuggestions))
    }

    private func acceptSuggestion(_ name: String) {
        guard let (directory, _) = autocompleteSplit(for: editor.text) else { return }
        editor.text = directory.appendingPathComponent(name).path + "/"
        refreshSuggestions(for: editor.text)
    }

    private func moveSuggestionHighlight(by delta: Int) {
        guard let current = highlightedSuggestionIndex else {
            highlightedSuggestionIndex = delta > 0 ? 0 : suggestions.count - 1
            return
        }
        highlightedSuggestionIndex = (current + delta + suggestions.count) % suggestions.count
    }

    private func clearSuggestions() {
        suggestionTask?.cancel()
        suggestions = []
        highlightedSuggestionIndex = nil
    }
}
