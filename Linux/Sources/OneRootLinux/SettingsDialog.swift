import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Settings: General, Appearance, Archives and Terminal. Every row reads and
/// writes the same preference the Mac's Settings does (the shared services
/// and `UserDefaults` keys), so a change takes effect right away.
@MainActor
final class SettingsDialog {
    private let dialog = PreferencesDialog()
    private let themes: ThemeStore
    private let defaults = UserDefaults.standard
    private weak var parent: AppWindow?
    private var watches: [ObservationWatch] = []
    private var themeChecks: [String: Image] = [:]
    private var fixedFolderRow: ActionRow?

    /// Runs when a setting that other windows show changed (their lists reload).
    var onChange: (() -> Void)?

    private let sessions: SessionKeeper
    private var sshPage: SSHSettingsPage?
    private var updatesGroup: UpdatesSettingsGroup?

    init(themes: ThemeStore, sessions: SessionKeeper, parent: AppWindow?) {
        self.themes = themes
        self.sessions = sessions
        self.parent = parent
        dialog.title = "Settings"
        dialog.contentWidth = 680
        dialog.contentHeight = 640
        dialog.searchEnabled = true
        dialog.add(generalPage())
        dialog.add(appearancePage())
        dialog.add(archivesPage())
        dialog.add(terminalPage())
        dialog.add(editorPage())
        let ssh = SSHSettingsPage(parent: { [weak self] in self?.dialog })
        sshPage = ssh
        dialog.add(ssh.page)
    }

    func present() {
        dialog.present(parent?.window)
    }

    // MARK: Pages

    private func generalPage() -> PreferencesPage {
        let page = PreferencesPage()
        page.title = "General"
        page.name = "general"
        page.iconName = "preferences-system-symbolic"

        let operations = PreferencesGroup()
        operations.title = "File Operations"
        operations.description = "Copying and moving."
        operations.add(switchRow(
            "Verify copies",
            "After copying or moving to another disk, read the copy back and compare it with the original, byte for byte. A copy that doesn\u{2019}t match is removed and the item fails, so you can retry; a move only deletes the original once its copy checks out. Takes about as long again as the copy.",
            active: defaults.bool(forKey: FileVerifier.enabledKey)
        ) { [defaults] on in defaults.set(on, forKey: FileVerifier.enabledKey) })
        operations.add(switchRow(
            "Copy to the same disk one at a time",
            "A copy or move to or from a disk another copy is already using waits for it to finish, instead of both running at once and slowing each other down. A waiting copy has Start Now.",
            active: defaults.object(forKey: FileTransferQueue.enabledKey) as? Bool ?? true
        ) { [defaults] on in defaults.set(on, forKey: FileTransferQueue.enabledKey) })
        page.add(operations)

        let browsing = PreferencesGroup()
        browsing.title = "Browsing"
        browsing.add(switchRow(
            "Friendly dates",
            "Dates from today and yesterday read \u{201C}Today at 5:57 PM\u{201D} and \u{201C}Yesterday at 9:17 PM\u{201D} in every date column, the Inspector and search results. Older dates are unchanged.",
            active: defaults.bool(forKey: FileDateFormat.usesRelativeDatesKey)
        ) { [defaults, weak self] on in
            defaults.set(on, forKey: FileDateFormat.usesRelativeDatesKey)
            self?.onChange?()
        })
        browsing.add(switchRow(
            "Always calculate folder sizes",
            "Works out every folder\u{2019}s size in the background as you browse, so the Size column and the Inspector always show it. Big folders can take a while. When this is off, select folders and choose Calculate Size.",
            active: FolderSizePreferenceStore.shared.calculateAll
        ) { on in FolderSizePreferenceStore.shared.set(on) })
        browsing.add(switchRow(
            "Warn before closing the last tab",
            "Applies to Ctrl+W and the tab\u{2019}s own close button; closing the last tab closes the window.",
            active: CloseLastTabPreferenceService().shouldWarn
        ) { on in CloseLastTabPreferenceService().setShouldWarn(on) })
        browsing.add(switchRow(
            "Reopen windows and tabs from last session",
            "At launch, opens the windows, tabs, split panes, sort orders and layout you had when you last quit. A folder that is gone opens Home instead. When this is off, OneRoot starts with one window and the saved session is forgotten.",
            active: sessions.isEnabled
        ) { [sessions] on in sessions.setEnabled(on) })
        page.add(browsing)

        let addressBar = PreferencesGroup()
        addressBar.title = "Address Bar"
        let styleRow = ComboRow()
        styleRow.title = "Address bar"
        styleRow.subtitle = "Clickable path shows where you are as segments to click, drop files on, or open for a subfolder menu; click its empty space or press Ctrl+L to type a path. Text field is always a plain, editable path."
        styleRow.subtitleLines = 0
        let styles = AddressBarStyle.allCases
        styleRow.setModel(StringList(styles.map(\.title)))
        styleRow.selected = styles.firstIndex(of: AddressBarStyle(rawValue: defaults.string(forKey: AddressBarStyle.storageKey) ?? "") ?? .breadcrumbs) ?? 0
        styleRow.onNotify(.custom("selected")) { [styleRow, defaults, weak self] in
            guard styles.indices.contains(styleRow.selected) else { return }
            defaults.set(styles[styleRow.selected].rawValue, forKey: AddressBarStyle.storageKey)
            self?.onChange?()
        }
        addressBar.add(styleRow)
        page.add(addressBar)

        let history = PreferencesGroup()
        history.title = "Navigation History"
        let clear = ButtonRow()
        clear.title = "Clear Navigation History"
        clear.onActivated {
            NavigationHistoryStore.shared.clear()
        }
        history.add(clear)
        page.add(history)
        if InstallMethod.current.checksForUpdates {
            let updates = UpdatesSettingsGroup(center: OneRootApp.updateCenter)
            updatesGroup = updates
            page.add(updates.group)
        }
        return page
    }

    private func appearancePage() -> PreferencesPage {
        let page = PreferencesPage()
        page.title = "Appearance"
        page.name = "appearance"
        page.iconName = "applications-graphics-symbolic"

        let automatic = PreferencesGroup()
        automatic.title = "Automatic"
        automatic.description = "Light or dark, following your desktop."
        automatic.add(themeRow(
            id: ThemeCatalog.automaticChoiceID, title: "OneRoot (Automatic)",
            detail: "The OneRoot look: white cards, blue folders and a soft blue selection. The default.",
            swatches: [ThemeCatalog.oneRootLight, ThemeCatalog.oneRootDark]
        ))
        automatic.add(themeRow(
            id: ThemeCatalog.nativeAutomaticChoiceID, title: "System (Automatic)",
            detail: "Your desktop\u{2019}s own libadwaita colors, untouched.",
            swatches: []
        ))
        page.add(automatic)

        var families: [String] = []
        for theme in ThemeCatalog.all where !families.contains(theme.family) && theme.family != "macOS" { families.append(theme.family) }
        for family in families {
            let group = PreferencesGroup()
            group.title = family
            let members = ThemeCatalog.all.filter { $0.family == family }
            for theme in members {
                group.add(themeRow(id: theme.id, title: members.count > 1 ? theme.name : theme.family, detail: nil, swatches: [theme]))
            }
            page.add(group)
        }

        let note = PreferencesGroup()
        note.description = "A theme sets OneRoot\u{2019}s backgrounds, text, selection and accent, and the colors of the sidebar\u{2019}s icons. File and folder icons in the list come from your icon theme and keep their own look."
        page.add(note)

        refreshThemeChecks()
        watches.append(ObservationWatch.watch({ [themes] in themes.choiceID }, emitsInitialValue: false) { [weak self] _ in
            self?.refreshThemeChecks()
        })
        return page
    }

    private func archivesPage() -> PreferencesPage {
        let settings = ArchiveSettingsService()
        let page = PreferencesPage()
        page.title = "Archives"
        page.name = "archives"
        page.iconName = "package-x-generic-symbolic"

        let group = PreferencesGroup()
        group.title = "Compress"
        group.description = "Used by Compress in the file menus. Archives are made with libarchive."

        let format = ComboRow()
        format.title = "Format"
        let formats = ArchiveFormat.allCases
        format.setModel(StringList(formats.map(\.displayName)))
        format.selected = formats.firstIndex(of: settings.format()) ?? 0
        format.onNotify(.custom("selected")) { [format] in
            let index = format.selected
            if formats.indices.contains(index) { ArchiveSettingsService().setFormat(formats[index]) }
        }
        group.add(format)

        let locations: [(ArchiveOutputLocation, String)] = [
            (.sameAsSource, "Next to the items"), (.fixedDirectory, "Always in one folder"), (.askEachTime, "Ask each time"),
        ]
        let location = ComboRow()
        location.title = "Save archives"
        location.setModel(StringList(locations.map(\.1)))
        location.selected = locations.firstIndex { $0.0 == settings.outputLocation() } ?? 0
        group.add(location)

        let folder = ActionRow()
        folder.title = "Folder"
        folder.subtitle = settings.fixedDirectory()?.path ?? "None chosen: archives go next to the items"
        let choose = Button(label: "Choose\u{2026}")
        choose.valign = GTK_ALIGN_CENTER
        choose.onClicked { [weak self, folder] in
            self?.parent?.chooseFolder(title: "Folder for Archives", accept: "Choose") { url in
                guard let url else { return }
                ArchiveSettingsService().setFixedDirectory(url)
                folder.subtitle = url.path
            }
        }
        folder.addSuffix(choose)
        folder.visible = settings.outputLocation() == .fixedDirectory
        fixedFolderRow = folder
        group.add(folder)

        location.onNotify(.custom("selected")) { [location, folder] in
            let index = location.selected
            guard locations.indices.contains(index) else { return }
            ArchiveSettingsService().setOutputLocation(locations[index].0)
            folder.visible = locations[index].0 == .fixedDirectory
        }
        page.add(group)
        return page
    }

    private func terminalPage() -> PreferencesPage {
        let preference = TerminalPreference()
        let page = PreferencesPage()
        page.title = "Terminal"
        page.name = "terminal"
        page.iconName = "utilities-terminal-symbolic"

        let group = PreferencesGroup()
        group.title = "Open in Terminal"
        group.description = "Leave this empty to use $TERMINAL, or the first installed terminal. A command may carry arguments, such as kitty --single-instance. The terminal starts in the folder."

        let entry = EntryRow()
        entry.title = "Terminal command"
        entry.text = preference.command ?? ""
        entry.showApplyButton = true
        let status = ActionRow()
        status.title = "In use"
        func describe() {
            switch TerminalPreference().resolve() {
            case .found(let executable, let arguments):
                status.subtitle = ([executable] + arguments).joined(separator: " ")
            case .missingConfigured(let command):
                status.subtitle = "\u{201C}\(command)\u{201D} isn\u{2019}t installed"
            case .noneFound:
                status.subtitle = "No terminal found"
            }
        }
        entry.onApply { [entry] in
            TerminalPreference().command = entry.text
            describe()
        }
        describe()
        group.add(entry)
        group.add(status)
        page.add(group)
        return page
    }

    private func editorPage() -> PreferencesPage {
        let page = PreferencesPage()
        page.title = "Editor"
        page.name = "editor"
        page.iconName = "text-editor-symbolic"
        let group = PreferencesGroup()
        group.title = "Open in Editor"
        group.description = "Adds \u{201C}Open in\u{201D} followed by the editor\u{2019}s name to a folder\u{2019}s right-click menu, opening the folder in the editor you choose. Leave it on None to hide it."
        let service = EditorPreferenceService()
        let editors = AppChooser.installedEditors()
        let row = ComboRow()
        row.title = "Editor"
        row.setModel(StringList(["None"] + editors.map(\.name)))
        let current = service.bundleIdentifier()
        row.selected = current.flatMap { id in editors.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        row.onNotify(.custom("selected")) { [row] in
            let index = row.selected
            service.setBundleIdentifier(index > 0 && editors.indices.contains(index - 1) ? editors[index - 1].id : nil)
        }
        group.add(row)
        if editors.isEmpty {
            let none = ActionRow()
            none.title = "No editor found"
            none.subtitle = "No installed app lists itself as a text editor or IDE."
            group.add(none)
        }
        page.add(group)
        return page
    }

    // MARK: Rows

    private func switchRow(_ title: String, _ subtitle: String, active: Bool, onToggle: @escaping @MainActor (Bool) -> Void) -> SwitchRow {
        let row = SwitchRow()
        row.title = title
        row.subtitle = subtitle
        row.subtitleLines = 0
        row.active = active
        row.onNotify(.custom("active")) { [row] in onToggle(row.active) }
        return row
    }

    private func themeRow(id: String, title: String, detail: String?, swatches: [Theme]) -> ActionRow {
        let row = ActionRow()
        row.title = title
        row.subtitle = detail
        row.subtitleLines = 0
        if !swatches.isEmpty {
            let label = Label("")
            label.markup = swatches.map(Self.swatchMarkup).joined(separator: "  ")
            row.addPrefix(label)
        }
        let check = Image(iconName: "object-select-symbolic")
        check.visible = false
        row.addSuffix(check)
        themeChecks[id] = check
        row.activatable = true
        row.onActivated { [themes] in themes.choose(id) }
        row.setAccessibleLabel(title)
        return row
    }

    private func refreshThemeChecks() {
        for (id, check) in themeChecks { check.visible = id == themes.choiceID }
    }

    /// A theme as four colored dots: text, sidebar, accent, folder.
    private static func swatchMarkup(_ theme: Theme) -> String {
        let colors: [ThemeColor] = [
            theme.surfaces?.text ?? ThemeColor(hex: theme.isDark ? 0xE6E6E6 : 0x262626),
            theme.surfaces?.sidebar ?? ThemeColor(hex: theme.isDark ? 0x2B2B2B : 0xEDEDED),
            theme.surfaces?.accent ?? ThemeColor(hex: 0x3584E4),
            theme.icons.folder,
        ]
        return colors.map { "<span foreground=\"\($0.hexString)\">\u{25CF}</span>" }.joined()
    }
}
