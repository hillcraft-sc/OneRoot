import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// File actions — Open, Cut/Copy/Paste, Rename, Trash, New Folder, Undo,
/// … — as window actions ("win.copy") shared by the context menus, the
/// keyboard and the main menu, acting on the focused pane's selection.
/// The view models do the work; this asks the questions they need.
extension AppWindow {
    var selection: [FileNode] { activePane?.selectedNodes ?? [] }

    private var isInTrash: Bool {
        activePane?.currentDirectory.map(Platform.isTrashFolder) ?? false
    }

    // MARK: Actions

    func addFileActions() {
        func action(_ name: String, _ accels: [String] = [], textAction: String? = nil, _ handler: @escaping @MainActor () -> Void) {
            let action = SimpleAction(name: name) { [weak self] in
                // Typing in the path bar or a dialog: Ctrl+C, Ctrl+V, …
                // belong to the text.
                if let textAction, let self, self.forwardToFocusedText(textAction) { return }
                handler()
            }
            window.addAction(action)
            fileActions[name] = action
            if !accels.isEmpty { app.application.setAccelerators(accels, for: "win.\(name)") }
        }
        action("open") { [weak self] in self?.openSelection() }
        action("quick-look") { [weak self] in
            guard let self, let pane = self.activePane else { return }
            self.app.toggleQuickLook(for: pane)
        }
        action("open-new-tab", ["<Control>Return"]) { [weak self] in
            guard let self else { return }
            for node in self.selection where node.isDirectory { self.viewModel.openNewTab(at: node.url, root: self.viewModel.activeTab?.hierarchyRoot, makeActive: false) }
        }
        action("open-with") { [weak self] in self?.openWithChooser() }
        action("cut", ["<Control>x"], textAction: "clipboard.cut") { [weak self] in
            guard let self, !self.selection.isEmpty, !self.isInTrash else { return }
            self.activePane?.cutSelection(self.selection)
        }
        action("copy", ["<Control>c"], textAction: "clipboard.copy") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.activePane?.copySelection(self.selection)
        }
        action("paste", ["<Control>v"], textAction: "clipboard.paste") { [weak self] in
            guard let pane = self?.activePane, pane.canPaste else { return }
            pane.paste()
        }
        action("duplicate") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.activePane?.duplicate(self.selection)
        }
        action("select-all", ["<Control>a"], textAction: "selection.select-all") { [weak self] in
            self?.focusedListPane?.selectAll()
        }
        action("rename") { [weak self] in self?.renameSelection() }
        action("trash") { [weak self] in
            guard let self, let pane = self.activePane, !self.selection.isEmpty, !self.isInTrash else { return }
            pane.moveToTrash(self.selection)
        }
        action("delete-permanently") { [weak self] in self?.deletePermanently() }
        action("restore") { [weak self] in
            guard let self, let pane = self.activePane, self.isInTrash, !self.selection.isEmpty else { return }
            pane.restore(self.selection)
        }
        action("new-folder", ["<Control><Shift>n"]) { [weak self] in self?.activePane?.promptForNewFolder() }
        action("new-folder-open") { [weak self] in self?.activePane?.promptForNewFolderAndOpen() }
        action("new-file") { [weak self] in self?.activePane?.promptForNewFile() }
        action("open-in-editor") { [weak self] in
            guard let self, self.selection.count == 1, self.selection[0].isDirectory,
                  let id = EditorPreferenceService().bundleIdentifier() else { return }
            if let error = AppChooser.launch(id, urls: [self.selection[0].url]) { self.showToast(error) }
        }
        action("new-folder-here") { [weak self] in
            guard let self, self.selection.count == 1, self.selection[0].isDirectory else { return }
            self.activePane?.promptForNewFolderHere(in: self.selection[0])
        }
        action("deselect-all", ["<Control><Shift>a"]) { [weak self] in self?.focusedListPane?.deselectAll() }
        action("undo", ["<Control>z"], textAction: "text.undo") { FileUndoCenter.shared.undo() }
        action("redo", ["<Control><Shift>z", "<Control>y"], textAction: "text.redo") { FileUndoCenter.shared.redo() }
        action("copy-path", ["<Control><Shift>c"]) { [weak self] in
            guard let self, let pane = self.activePane else { return }
            let urls = self.selection.isEmpty ? pane.currentDirectory.map { [$0] } ?? [] : self.selection.map(\.url)
            pane.copyPaths(urls)
            self.showToast(urls.count == 1 ? "Copied the path" : "Copied \(urls.count) paths")
        }
        action("copy-name") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.activePane?.copyNames(self.selection, includeExtension: true)
        }
        action("copy-name-no-ext") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.activePane?.copyNames(self.selection, includeExtension: false)
        }
        action("show-in-file-manager", ["<Control><Shift>e"]) { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.showInFileManager(self.selection.map(\.url))
        }
        action("compress") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            self.activePane?.compressSelection(self.selection)
        }
        action("extract") { [weak self] in
            guard let self, let pane = self.activePane, pane.canExtract(self.selection) else { return }
            pane.extractSelection(self.selection)
        }
        action("open-terminal") { [weak self] in
            guard let self else { return }
            let folder = self.selection.count == 1 && self.selection[0].isDirectory ? self.selection[0].url : self.activePane?.currentDirectory
            if let folder { self.openTerminal(at: folder) }
        }
        action("copy-via-ssh") { [weak self] in
            guard let self, !self.selection.isEmpty else { return }
            SSHCopyDialog.present(files: self.selection.map(\.url), window: self)
        }
        action("connect-to-server", ["<Control>k"]) { [weak self] in
            guard let self else { return }
            ConnectToServerDialog.present(window: self)
        }
        action("browse-network", ["<Control><Shift>k"]) { [weak self] in
            guard let self else { return }
            BrowseNetworkDialog.present(window: self)
        }
        action("pin") { [weak self] in
            guard let self else { return }
            let folders = self.selection.filter(\.isDirectory).map(\.url)
            let targets = folders.isEmpty ? (self.activePane?.currentDirectory.map { [$0] } ?? []) : folders
            for url in targets { PinnedLocationsStore.shared.toggle(url) }
        }
        action("copy-to-other", ["F5"]) { [weak self] in self?.viewModel.sendSelectionToOtherPane(move: false) }
        action("move-to-other", ["F6"]) { [weak self] in self?.viewModel.sendSelectionToOtherPane(move: true) }
        let openWithApp = SimpleAction(name: "open-with-app", parameterType: "s") { [weak self] parameter in
            guard let self, let id = parameter.stringValue else { return }
            let files = self.selection.filter { !$0.isDirectory }.map(\.url)
            if let error = AppChooser.launch(id, urls: files) { self.showToast(error) }
        }
        window.addAction(openWithApp)
        for quick in QuickAction.allCases {
            action("qa-\(quick.rawValue)") { [weak self] in
                guard let self, let pane = self.activePane else { return }
                pane.promptQuickAction(quick, for: self.selection)
            }
        }
        action("calculate-size") { [weak self] in
            guard let self, let pane = self.activePane else { return }
            let folders = self.selection.filter(\.isDirectory)
            if folders.isEmpty { pane.calculateFolderSizesInView() } else { pane.calculateFolderSizes(folders) }
        }
    }

    /// Hands a clipboard/undo shortcut to the text field being typed in.
    private func forwardToFocusedText(_ action: String) -> Bool {
        guard let focus = gtk_window_get_focus(window.castedPointer()),
              g_type_check_instance_is_a(UnsafeMutableRawPointer(focus).assumingMemoryBound(to: GTypeInstance.self), gtk_editable_get_type()) != 0 else {
            return false
        }
        _ = gtk_widget_activate_action_variant(focus, action, nil)
        return true
    }

    /// Greys out what doesn't apply to the focused pane's selection.
    func updateFileActions() {
        guard let pane = activePane else { return }
        let nodes = pane.selectedNodes
        let trash = isInTrash
        let has = !nodes.isEmpty
        let enabled: [String: Bool] = [
            "open": has, "open-new-tab": nodes.contains(where: \.isDirectory), "open-with": nodes.count == 1 && !nodes[0].isDirectory,
            "cut": has && !trash, "copy": has, "duplicate": has && !trash, "rename": has && !trash,
            "trash": has && !trash, "delete-permanently": has, "restore": has && trash,
            "new-folder": pane.currentDirectory != nil && !trash, "new-folder-open": pane.currentDirectory != nil && !trash,
            "new-file": pane.currentDirectory != nil && !trash, "compress": has && !trash,
            "extract": has && !trash && pane.canExtract(nodes), "copy-name": has, "copy-name-no-ext": has, "show-in-file-manager": has,
            "copy-via-ssh": has && !trash && nodes.allSatisfy { $0.url.isFileURL },
        ]
        for (name, isEnabled) in enabled { fileActions[name]?.enabled = isEnabled }
        let available = Set(pane.quickActionOptions(for: nodes).filter(\.isAvailable).map(\.action))
        for quick in QuickAction.allCases { fileActions["qa-\(quick.rawValue)"]?.enabled = available.contains(quick) }
    }

    // MARK: Opening

    func openSelection() {
        guard let pane = activePane else { return }
        let nodes = pane.selectedNodes
        if nodes.count == 1, let node = nodes.first, node.isNavigable(browsePackage: false) {
            pane.navigate(to: node.url)
            return
        }
        for node in nodes {
            if node.isDirectory {
                viewModel.openNewTab(at: node.url, root: viewModel.activeTab?.hierarchyRoot, makeActive: false)
            } else {
                open(node.url)
            }
        }
    }

    /// Open With: the desktop's app chooser for the selected file.
    func openWithChooser() {
        guard let node = selection.first, !node.isDirectory else { return }
        AppChooser.present(for: node.url, parent: window) { [weak self] error in
            if let error { self?.showToast(error) }
        }
    }

    /// The user's terminal, opened in `folder` (`TerminalPreference`: the
    /// command from Settings, then $TERMINAL, then the usual terminals).
    /// Selects the items in the desktop's file manager
    /// (`org.freedesktop.FileManager1.ShowItems`); without one, opens the
    /// containing folder. Runs off the main thread.
    func showInFileManager(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let uris = "[" + urls.map { "'\($0.absoluteString)'" }.joined(separator: ", ") + "]"
        let parent = first.deletingLastPathComponent().path
        Task.detached { [weak self] in
            func run(_ tool: String, _ arguments: [String]) -> Bool {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [tool] + arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return false }
                process.waitUntilExit()
                return process.terminationStatus == 0
            }
            let shown = run("gdbus", ["call", "--session", "--dest", "org.freedesktop.FileManager1",
                                      "--object-path", "/org/freedesktop/FileManager1",
                                      "--method", "org.freedesktop.FileManager1.ShowItems", uris, ""])
            if shown || run("xdg-open", [parent]) { return }
            await MainActor.run { self?.showToast("Couldn\u{2019}t open a file manager.") }
        }
    }

    func openTerminal(at folder: URL) {
        switch TerminalPreference().resolve() {
        case .noneFound:
            showToast("No terminal app was found. Choose one in Settings, or set the TERMINAL environment variable.")
        case .missingConfigured(let command):
            showToast("The terminal set in Settings (\u{201C}\(command)\u{201D}) isn\u{2019}t installed.")
        case .found(let executable, let arguments):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = folder
            do {
                try process.run()
            } catch {
                showToast("Couldn\u{2019}t open \(URL(fileURLWithPath: executable).lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Questions

    private func renameSelection() {
        guard let pane = activePane, let node = selection.first, !isInTrash else { return }
        guard selection.count == 1 else {
            // Several: one rule for all of them, with a preview.
            let nodes = selection
            BatchRenameDialog.present(urls: nodes.map(\.url), parent: window) { [weak pane] newNames in
                pane?.applyBatchRename(urls: nodes.map(\.url), newNames: newNames)
            }
            return
        }
        pane.promptRename(node)
    }

    private func deletePermanently() {
        guard let pane = activePane, !selection.isEmpty else { return }
        let nodes = selection
        let heading = nodes.count == 1 ? "Delete \u{201C}\(nodes[0].name)\u{201D} Permanently?" : "Delete \(nodes.count) Items Permanently?"
        let dialog = Dialogs.alert(heading: heading, body: "This can't be undone.",
                                   responses: [("cancel", "Cancel"), ("delete", "Delete")], destructive: "delete")
        dialog.onResponse { response in
            guard response == "delete" else { return }
            pane.deletePermanently(nodes)
        }
        dialog.present(window)
    }

    /// What a pane's view model asks for: names, conflicts, destinations.
    func watchPrompts(of pane: FileListViewModel) -> [ObservationWatch] {
        var watches: [ObservationWatch] = []
        watches.append(ObservationWatch.watch({ pane.pendingRenameNode }) { [weak self, weak pane] node in
            guard let self, let pane, let node else { return }
            pane.pendingRenameNode = nil
            Dialogs.promptName(heading: "Rename", initial: node.name, confirm: "Rename", selectsStem: !node.isDirectory, parent: self.window) { name in
                guard name != node.name else { return }
                pane.rename(node, to: name)
            }
        })
        watches.append(ObservationWatch.watch({ pane.pendingNewFolderIntent != nil }) { [weak self, weak pane] isPending in
            guard let self, let pane, isPending else { return }
            let name = Self.untitled("New Folder", in: pane)
            Dialogs.promptName(heading: "New Folder", initial: name, confirm: "Create", selectsStem: false, parent: self.window) { name in
                pane.createFolder(named: name)
            }
            // Cancelling leaves the intent; the next prompt replaces it.
        })
        watches.append(ObservationWatch.watch({ pane.pendingNewFileIntent }) { [weak self, weak pane] isPending in
            guard let self, let pane, isPending else { return }
            let name = Self.untitled("New File.txt", in: pane)
            Dialogs.promptName(heading: "New File", initial: name, confirm: "Create", selectsStem: true, parent: self.window) { name in
                pane.createFile(named: name)
            }
        })
        watches.append(ObservationWatch.watch({ pane.pendingQuickAction?.id }) { [weak self, weak pane] id in
            guard let self, let pane, id != nil, let pending = pane.pendingQuickAction else { return }
            QuickActionDialog.present(pending, parent: self.window, onRun: { request, plan in
                pane.runQuickAction(request, plan: plan)
            }, onCancel: {
                pane.pendingQuickAction = nil
            })
        })
        watches.append(ObservationWatch.watch({ pane.pendingConflicts?.id }) { [weak self, weak pane] id in
            guard let self, let pane, id != nil, let request = pane.pendingConflicts else { return }
            Dialogs.resolveConflicts(request, parent: self.window) { answer in pane.answerConflicts(answer, to: request.id) }
        })
        watches.append(ObservationWatch.watch({ pane.pendingNameFix?.id }) { [weak self, weak pane] id in
            guard let self, let pane, id != nil, let request = pane.pendingNameFix else { return }
            Dialogs.resolveNameFixes(request, parent: self.window) { answer in pane.answerNameFix(answer, to: request.id) }
        })
        watches.append(ObservationWatch.watch({ pane.pendingRestoreDestinationItemName }) { [weak self, weak pane] name in
            guard let self, let pane, let name else { return }
            self.chooseFolder(title: "Where Should \u{201C}\(name)\u{201D} Go?", accept: "Restore") { pane.resolveRestoreDestination($0) }
        })
        watches.append(ObservationWatch.watch({ pane.pendingArchiveDestinationItemName }) { [weak self, weak pane] name in
            guard let self, let pane, let name else { return }
            self.chooseFolder(title: "Save the Archive of \u{201C}\(name)\u{201D}", accept: "Compress") { pane.resolveArchiveDestination($0) }
        })
        watches.append(ObservationWatch.watch({ pane.pendingExtractDestinationItemName }) { [weak self, weak pane] name in
            guard let self, let pane, let name else { return }
            self.chooseFolder(title: "Extract \u{201C}\(name)\u{201D} To", accept: "Extract") { pane.resolveExtractDestination($0) }
        })
        watches.append(ObservationWatch.watch({ pane.pendingOpenInNewTabDirectory }) { [weak self, weak pane] url in
            guard let self, let pane, let url else { return }
            pane.clearPendingOpenInNewTabDirectory()
            self.viewModel.openNewTab(at: url, root: self.viewModel.activeTab?.hierarchyRoot)
        })
        watches.append(ObservationWatch.watch({ pane.addressEditTrigger }, emitsInitialValue: false) { [weak self] _ in
            self?.pathBar.beginEditing()
        })
        watches.append(ObservationWatch.watch({ (pane.selectedNodes.map(\.url), pane.currentDirectory) }) { [weak self, weak pane] _ in
            guard let self, let pane, pane === self.activePane else { return }
            self.updateFileActions()
        })
        return watches
    }

    /// "New Folder", or "New Folder 2" if that's taken.
    private static func untitled(_ base: String, in pane: FileListViewModel) -> String {
        let taken = Set(pane.items.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        let stem = (base as NSString).deletingPathExtension
        let ext = (base as NSString).pathExtension
        for number in 2... {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
        }
        return base
    }

    func chooseFolder(title: String, accept: String, completion: @escaping (URL?) -> Void) {
        let dialog = FileDialog()
        dialog.title = title
        dialog.acceptLabel = accept
        dialog.modal = true
        dialog.selectFolder(parent: window) { result in
            switch result {
            case .success(let path?): completion(URL(fileURLWithPath: path, isDirectory: true))
            default: completion(nil)
            }
        }
    }

    // MARK: Context menus

    /// The right-click menu for the focused pane: the selection's, or the
    /// folder's when nothing is selected.
    func showContextMenu(in pane: FileListPane, x: Double, y: Double) {
        updateFileActions()
        let nodes = pane.viewModel.selectedNodes
        let menu = GMenuRef()
        func section(_ items: [(String, String)]) {
            let section = GMenuRef()
            for (label, action) in items { section.append(label, action: action) }
            menu.appendSection(nil, section: section)
        }
        let isSplit = viewModel.activeTab?.isSplit ?? false
        if nodes.isEmpty {
            if isInTrash { section([("Empty Trash…", "win.empty-trash")]) }
            section([("New Folder", "win.new-folder"), ("New File", "win.new-file")])
            section([("Paste", "win.paste"), ("Select All", "win.select-all")])
            section([("Open in Terminal", "win.open-terminal"), ("Copy Path", "win.copy-path"),
                     (PinnedLocationsStore.shared.isPinned(pane.viewModel.currentDirectory ?? URL(fileURLWithPath: "/")) ? "Remove from Sidebar" : "Pin to Sidebar", "win.pin")])
            section([("Calculate Folder Sizes", "win.calculate-size"), ("Show Hidden Files", "win.show-hidden")])
        } else if isInTrash {
            section([("Restore", "win.restore"), ("Delete Permanently…", "win.delete-permanently")])
            section([("Empty Trash…", "win.empty-trash"), ("Copy Path", "win.copy-path")])
        } else {
            let folders = nodes.filter(\.isDirectory)
            var open: [(String, String)] = [("Open", "win.open"), ("Quick Look", "win.quick-look")]
            if !folders.isEmpty { open.append(("Open in New Tab", "win.open-new-tab")) }
            section(open)
            if folders.isEmpty, let first = nodes.first {
                let apps = GMenuRef()
                for app in AppChooser.apps(for: first.url).prefix(8) {
                    let item = GMenuItemRef(label: app.name, action: "win.open-with-app")
                    item.setTargetValue(Variant.string(app.id))
                    apps.appendItem(item)
                }
                let other = GMenuRef()
                if nodes.count == 1 { other.append("Other App…", action: "win.open-with") }
                apps.appendSection(nil, section: other)
                let submenu = GMenuRef()
                submenu.appendSubmenu("Open With", submenu: apps)
                menu.appendSection(nil, section: submenu)
            }
            var edit: [(String, String)] = [("Cut", "win.cut"), ("Copy", "win.copy"), ("Duplicate", "win.duplicate")]
            if isSplit { edit += [("Copy to Other Pane", "win.copy-to-other"), ("Move to Other Pane", "win.move-to-other")] }
            section(edit)
            section([("Rename…", "win.rename"), ("Move to Trash", "win.trash")])
            var archive: [(String, String)] = [("Compress", "win.compress")]
            if pane.viewModel.canExtract(nodes) { archive.append(("Extract", "win.extract")) }
            archive.append(("Copy Path", "win.copy-path"))
            section(archive)
            let quick = Self.quickActionsMenu(for: pane.viewModel.quickActionOptions(for: nodes))
            if let quick {
                let quickSection = GMenuRef()
                quickSection.appendSubmenu("Quick Actions", submenu: quick)
                menu.appendSection(nil, section: quickSection)
            }
            // The rarer ones, so the menu stays short enough for a small window.
            let more = GMenuRef()
            if nodes.count == 1 { more.append("Get Info", action: "win.get-info") }
            more.append(nodes.count == 1 ? "Copy Name" : "Copy Names", action: "win.copy-name")
            more.append(nodes.count == 1 ? "Copy Name without Extension" : "Copy Names without Extensions", action: "win.copy-name-no-ext")
            more.append("Show in File Manager", action: "win.show-in-file-manager")
            more.append("Copy via SSH\u{2026}", action: "win.copy-via-ssh")
            if folders.count == 1 && nodes.count == 1 {
                more.append("New Folder Here", action: "win.new-folder-here")
                if let id = EditorPreferenceService().bundleIdentifier(), let name = AppChooser.name(of: id) {
                    more.append("Open in \(name)", action: "win.open-in-editor")
                }
                more.appendSubmenu("Add to Workspace", submenu: addToWorkspaceMenu(for: folders[0].url))
                more.append("Open in Terminal", action: "win.open-terminal")
                more.append(PinnedLocationsStore.shared.isPinned(folders[0].url) ? "Remove from Sidebar" : "Pin to Sidebar", action: "win.pin")
            }
            if !folders.isEmpty { more.append("Calculate Size", action: "win.calculate-size") }
            more.append("Delete Permanently…", action: "win.delete-permanently")
            let moreSection = GMenuRef()
            moreSection.appendSubmenu("More", submenu: more)
            menu.appendSection(nil, section: moreSection)
        }
        pane.showMenu(menu, x: x, y: y)
    }

    /// The Quick Actions that apply to a selection as a menu (unavailable
    /// ones greyed, with why), or `nil` when none is relevant.
    static func quickActionsMenu(for options: [QuickActionOption]) -> GMenuRef? {
        guard !options.isEmpty else { return nil }
        let menu = GMenuRef()
        for option in options {
            let title = option.isAvailable ? option.action.menuTitle : "\(option.action.menuTitle) \u{2014} \(option.unavailableReason ?? "")"
            menu.append(title, action: "win.qa-\(option.action.rawValue)")
        }
        return menu
    }
}
