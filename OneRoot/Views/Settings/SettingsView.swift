import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The app's ⌘,-accessible Settings window (`OneRootApp`'s `Settings`
/// scene) — styled after macOS's own System Settings: a sidebar of
/// categories (colored icon badge + label) on the left, the selected
/// category's content on the right, with each pane's own controls grouped
/// into rounded-card `Form` sections (`.formStyle(.grouped)`) instead of a
/// plain list. Was a top `TabView` before; that read as a row of browser
/// tabs, not a native settings window, and gave each pane its own ad hoc
/// mix of `Form` rows and free-floating help text.
struct SettingsView: View {
    @State private var selection: SettingsCategory? = .general
    @State private var hostWindow: NSWindow?

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label {
                    Text(category.title)
                } icon: {
                    SettingsIconBadge(systemName: category.symbolName, color: category.tintColor)
                }
                .tag(category)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                // Capped, not left to fill the detail column — a `Form`
                // section otherwise stretches edge-to-edge with whatever
                // width the window happens to be, which (window resizing
                // being what it is) reads as a lot of dead space rather
                // than the fixed-width card layout System Settings itself
                // uses regardless of how wide its window gets.
                VStack(alignment: .trailing, spacing: 0) {
                    (selection ?? .general).content
                    HelpButton(topic: (selection ?? .general).helpTopic)
                        .padding(.trailing, 20)
                }
                .frame(maxWidth: 420)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle((selection ?? .general).title)
        }
        .frame(width: 620, height: 480)
        .background {
            WindowAccessor(window: $hostWindow)
        }
        // `isRestorable = false` (set by `WindowAccessor`) only stops
        // AppKit's modern state-restoration system — this window's size is
        // separately governed by the older `NSWindow` frame-autosave
        // mechanism SwiftUI wires up automatically for `Settings` scenes
        // (the "NSWindow Frame com_apple_SwiftUI_Settings_window" default),
        // which re-saves itself on every move/resize independent of that
        // flag. A `Settings` window has no real reason to be user-resizable
        // here — every pane's content is a fixed-width card regardless —
        // so this clears that autosave name outright (stops it saving *or*
        // restoring a size) and forces today's ideal size once, rather than
        // leaving this class of stale-size bug able to recur.
        .onChange(of: hostWindow) { _, window in
            guard let window else { return }
            window.setFrameAutosaveName("")
            window.setContentSize(NSSize(width: 620, height: 480))
            window.styleMask.remove(.resizable)
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case terminal
    case editor
    case ssh
    case archives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .terminal: return "Terminal"
        case .editor: return "Editor"
        case .ssh: return "SSH"
        case .archives: return "Archives"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .terminal: return "terminal.fill"
        case .editor: return "chevron.left.forwardslash.chevron.right"
        case .ssh: return "network"
        case .archives: return "archivebox.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .terminal: return .indigo
        case .editor: return .blue
        case .ssh: return .green
        case .archives: return .orange
        }
    }

    /// What the pane's **?** button opens.
    var helpTopic: HelpTopicID {
        switch self {
        case .general, .editor: return .settings
        case .appearance: return .themes
        case .terminal: return .terminal
        case .ssh: return .copyViaSSH
        case .archives: return .compress
        }
    }

    @ViewBuilder var content: some View {
        switch self {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .terminal: TerminalSettingsView()
        case .editor: EditorSettingsView()
        case .ssh: SSHSettingsView()
        case .archives: ArchiveSettingsView()
        }
    }
}

/// The colored rounded-square icon badge System Settings uses in its own
/// sidebar (General's gray gear, Network's blue globe, …) — a plain SF
/// Symbol next to text reads as a generic app sidebar, not this
/// specifically native-feeling one.
private struct SettingsIconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// Last-tab close confirmation (see `CloseLastTabConfirmation`) plus the
/// navigation-history depth (see `NavigationHistoryStore` / the Go menu's
/// Recent Locations submenu).
private struct GeneralSettingsView: View {
    @State private var warnBeforeClosingLastTab = true
    @State private var reopenSession = SessionService().isEnabled
    @AppStorage(AddressBarStyle.storageKey) private var addressBarStyle: AddressBarStyle = .breadcrumbs
    @AppStorage(FileOperationProgressCenter.showsProgressInWindowKey) private var showsProgressInWindow = false
    @AppStorage(FileVerifier.enabledKey) private var verifiesCopies = false
    @AppStorage(FileTransferQueue.enabledKey) private var copiesOneAtATime = true
    @AppStorage(FileSystemService.keepsMetadataOnSharesKey) private var keepsMetadataOnShares = false
    @AppStorage(UpdateCenter.checksAutomaticallyKey) private var checksForUpdates = false
    @AppStorage(FileSystemService.usesSpotlightLastOpenedKey) private var usesSpotlightLastOpened = false
    @AppStorage(FileDateFormat.usesRelativeDatesKey) private var usesRelativeDates = false
    private let preferenceService = CloseLastTabPreferenceService()
    private var history = NavigationHistoryStore.shared
    private var folderSizes = FolderSizePreferenceStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Reopen windows and tabs from last session", isOn: $reopenSession)
                    .onChange(of: reopenSession) { _, newValue in
                        SessionService().setEnabled(newValue)
                    }
            } footer: {
                Text("When OneRoot opens, bring back the windows and tabs that were open when it quit: their folders, sort order, and split panes. Folders that no longer exist open at your home folder instead.")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
            } footer: {
                Text("Off unless you turn it on. Once a day, OneRoot then asks GitHub whether a newer version has been released, and shows its notes if there is one. It sends nothing about you or your files, and never downloads or installs anything by itself. OneRoot \u{25B8} Check for Updates\u{2026} checks any time.")
            }

            Section {
                Toggle("Warn before closing the last tab", isOn: $warnBeforeClosingLastTab)
                    .onChange(of: warnBeforeClosingLastTab) { _, newValue in
                        preferenceService.setShouldWarn(newValue)
                    }
            } footer: {
                Text("Applies to \u{2318}W and each tab's own close button.")
            }

            Section {
                Toggle("Show progress in the window", isOn: $showsProgressInWindow)
            } footer: {
                Text("Copying, moving, compressing, or extracting opens the File Operations card at the bottom of the window, instead of a separate progress window for each one.")
            }

            Section {
                Toggle("Verify copies", isOn: $verifiesCopies)
            } footer: {
                Text("After copying or moving to another disk, read the copy back and compare it with the original, byte for byte. A copy that doesn\u{2019}t match is removed and the item fails, so you can try again; a move only deletes the original once its copy checks out. Takes about as long again as the copy. Copies within one disk are clones of the original and aren\u{2019}t checked.")
            }

            Section {
                Toggle("Keep Mac metadata on NFS shares", isOn: $keepsMetadataOnShares)
            } footer: {
                Text("Shares that can\u{2019}t store Mac metadata themselves (NFS) get it as a hidden \u{201C}._\u{201D} file beside every item, which can make copying many small files many times slower. With this off, copies there carry contents, permissions, and dates, but not Finder tags, \u{201C}Where from\u{201D}, quarantine flags, or resource forks. Disks and SMB shares always get everything.")
            }

            Section {
                Toggle("Copy to the same disk one at a time", isOn: $copiesOneAtATime)
            } footer: {
                Text("A copy or move to or from a disk another copy is already using waits for it to finish, instead of both running at once and slowing each other down (especially on hard drives and network shares). Copies between other disks still run side by side. A waiting copy has Start Now.")
            }

            Section {
                Toggle("Friendly dates", isOn: $usesRelativeDates)
                    .onChange(of: usesRelativeDates) { _, _ in
                        NotificationCenter.default.post(name: .fileListDatesChanged, object: nil)
                    }
            } footer: {
                Text("Dates from today and yesterday read \u{201C}Today at 5:57 PM\u{201D} and \u{201C}Yesterday at 9:17 PM\u{201D}, the way Finder shows them, in every date column, the Inspector, and search results. Older dates are unchanged.")
            }

            Section {
                Toggle("Date Last Opened: use Spotlight's date, like Finder", isOn: $usesSpotlightLastOpened)
                    .onChange(of: usesSpotlightLastOpened) { _, _ in
                        NotificationCenter.default.post(name: .fileListDatesChanged, object: nil)
                    }
            } footer: {
                Text("Off: the Date Last Opened column shows when a file was last read by anything, which updates more often than you'd expect (backups, searches, apps checking it). On: it shows when you last opened it, the way Finder does — but each folder asks Spotlight about every item as it loads, which can make big folders slower. Recents always uses Spotlight's date.")
            }

            Section {
                Toggle("Always calculate folder sizes", isOn: Binding(
                    get: { folderSizes.calculateAll },
                    set: { folderSizes.set($0) }
                ))
            } footer: {
                Text("Works out every folder's size in the background as you browse, so the Size column and the Inspector always show it. Big folders can take a while. When this is off, select folders and choose Calculate Size.")
            }

            Section {
                Picker("Address bar", selection: $addressBarStyle) {
                    ForEach(AddressBarStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
            } footer: {
                Text("""
                Clickable path shows where you are as segments you can click, \
                drop files on, or open (\u{203A}) for a subfolder menu; click its \
                empty space or press \u{21E7}\u{2318}G to type a path. Text field is \
                always a plain, editable path.
                """)
            }

            Section {
                Stepper(
                    value: Binding(get: { history.limit }, set: { history.setLimit($0) }),
                    in: NavigationHistoryService.limitRange
                ) {
                    LabeledContent("Locations to remember", value: "\(history.limit)")
                }

                Button("Clear Navigation History") { history.clear() }
                    .disabled(history.entries.isEmpty)
            } header: {
                Text("Navigation History")
            } footer: {
                Text("""
                How many folders you've visited to keep, newest first (default \
                \(NavigationHistoryService.defaultLimit)). The Go menu's \
                Recent Locations submenu shows the most recent 12; \
                "Show All History…" there opens the full list. Lowering this \
                trims the history right away.
                """)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            warnBeforeClosingLastTab = preferenceService.shouldWarn
        }
    }
}

/// Which terminal app "Open in Terminal" launches — see
/// `TerminalPreferenceService`.
private struct TerminalSettingsView: View {
    @State private var terminalAppURL: URL?
    @State private var terminalBundleIdentifier: String?
    @State private var workingDirectoryFlag = ""
    @State private var showingChooseTerminalApp = false
    private let preferenceService = TerminalPreferenceService()

    /// Confirmed by direct reproduction against the installed Tabby 1.0.235
    /// binary: its bundled `open` CLI command throws an uncaught
    /// `mixin.stripAnsi is not a function` inside yargs/cliui before Tabby's
    /// own handler runs, so the launched process sits with no window and
    /// never exits. The "open" argument in the footer below is the correct,
    /// documented syntax — this is a bug in Tabby itself, not in how OneRoot
    /// invokes it, so the warning only makes sense when Tabby is actually
    /// the selected app — not for every custom terminal.
    private static let tabbyBundleIdentifier = "org.tabby"

    var body: some View {
        Form {
            Section {
                // A single popup menu showing the current app's icon + name
                // — the same idiom System Settings uses for "Default web
                // browser" etc. — rather than a label, a value row, and a
                // second row of action buttons underneath.
                LabeledContent("Terminal App") {
                    Menu {
                        Button("Choose…", action: chooseTerminalApp)
                        if terminalAppURL != nil {
                            Divider()
                            Button("Use Default Terminal", action: resetTerminalApp)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let terminalAppURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: terminalAppURL.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(FileManager.default.displayName(atPath: terminalAppURL.path))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Terminal (Default)")
                            }
                        }
                    }
                    .fixedSize()
                }

                if terminalAppURL != nil {
                    LabeledContent("Open-Folder Argument") {
                        VStack(alignment: .trailing, spacing: 3) {
                            TextField("", text: $workingDirectoryFlag)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onChange(of: workingDirectoryFlag) { _, newValue in
                                    preferenceService.setWorkingDirectoryFlag(newValue)
                                }
                            Text("e.g. open, or --cwd")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if terminalAppURL != nil {
                    Text("""
                    Most terminals open at the given folder automatically. A few \
                    (Tabby, kitty, Alacritty…) need one extra argument first — check \
                    that app's docs. Tabby's is the word "open" \
                    ("tabby open /some/folder"). Leave blank to just launch the app \
                    without changing its folder.
                    """)
                }
            }

            if terminalBundleIdentifier == Self.tabbyBundleIdentifier {
                Section {
                    Label {
                        Text("""
                        Known issue: Tabby 1.0.235's own "open" command currently \
                        crashes before showing a window (a bug in Tabby's bundled \
                        dependencies, not in OneRoot). It launches but stays blank. \
                        Watch for a Tabby update that fixes this.
                        """)
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCurrentSelection)
        .sheet(isPresented: $showingChooseTerminalApp) {
            FileChooserView(
                startingAt: URL(fileURLWithPath: "/Applications"),
                canChooseFiles: true,
                canChooseDirectories: false,
                allowedContentTypes: [.application]
            ) { url in
                guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { return }
                preferenceService.setBundleIdentifier(bundleIdentifier)
                terminalAppURL = url
                terminalBundleIdentifier = bundleIdentifier
            }
        }
    }

    private func loadCurrentSelection() {
        workingDirectoryFlag = preferenceService.workingDirectoryFlag() ?? ""
        terminalBundleIdentifier = preferenceService.bundleIdentifier()
        guard let bundleIdentifier = terminalBundleIdentifier else {
            terminalAppURL = nil
            return
        }
        terminalAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private func chooseTerminalApp() {
        showingChooseTerminalApp = true
    }

    private func resetTerminalApp() {
        preferenceService.setBundleIdentifier(nil)
        preferenceService.setWorkingDirectoryFlag(nil)
        workingDirectoryFlag = ""
        terminalAppURL = nil
        terminalBundleIdentifier = nil
    }
}

/// Which editor app the folder Open With menu's pinned "Editor" entry
/// launches — see `EditorPreferenceService`/`openInEditor`. Unlike
/// `TerminalSettingsView`, there's no "default" to fall back to: macOS
/// doesn't bundle an editor the way it bundles Terminal.app, so "None" is
/// a real, expected steady state, not just a transient one before the
/// user picks something.
private struct EditorSettingsView: View {
    @State private var editorAppURL: URL?
    @State private var workingDirectoryFlag = ""
    @State private var showingChooseEditorApp = false
    private let preferenceService = EditorPreferenceService()

    var body: some View {
        Form {
            Section {
                LabeledContent("Editor App") {
                    Menu {
                        Button("Choose…", action: chooseEditorApp)
                        if editorAppURL != nil {
                            Divider()
                            Button("None", action: resetEditorApp)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let editorAppURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: editorAppURL.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(FileManager.default.displayName(atPath: editorAppURL.path))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("None")
                            }
                        }
                    }
                    .fixedSize()
                }

                if editorAppURL != nil {
                    LabeledContent("Open-Folder Argument") {
                        VStack(alignment: .trailing, spacing: 3) {
                            TextField("", text: $workingDirectoryFlag)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onChange(of: workingDirectoryFlag) { _, newValue in
                                    preferenceService.setWorkingDirectoryFlag(newValue)
                                }
                            Text("usually blank")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if editorAppURL != nil {
                    Text("""
                    A folder's Open With menu gets a pinned entry for this \
                    editor, in addition to whatever else macOS already knows \
                    can open folders (Zed, for example). This is what makes \
                    an editor like VS Code show up there too — it opens \
                    folders fine, it just doesn't advertise that to macOS the \
                    way Zed does, so without a pinned entry it wouldn't appear \
                    in that menu at all (the same reason it's missing from \
                    Finder's own folder Open With). Most editors, including \
                    VS Code, open at the given folder automatically with no \
                    extra argument — leave this blank unless yours needs one.
                    """)
                } else {
                    Text("Pick an editor to pin it to every folder's Open With menu.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCurrentSelection)
        .sheet(isPresented: $showingChooseEditorApp) {
            FileChooserView(
                startingAt: URL(fileURLWithPath: "/Applications"),
                canChooseFiles: true,
                canChooseDirectories: false,
                allowedContentTypes: [.application]
            ) { url in
                guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { return }
                preferenceService.setBundleIdentifier(bundleIdentifier)
                editorAppURL = url
            }
        }
    }

    private func loadCurrentSelection() {
        workingDirectoryFlag = preferenceService.workingDirectoryFlag() ?? ""
        guard let bundleIdentifier = preferenceService.bundleIdentifier() else {
            editorAppURL = nil
            return
        }
        editorAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private func chooseEditorApp() {
        showingChooseEditorApp = true
    }

    private func resetEditorApp() {
        preferenceService.setBundleIdentifier(nil)
        preferenceService.setWorkingDirectoryFlag(nil)
        workingDirectoryFlag = ""
        editorAppURL = nil
    }
}
