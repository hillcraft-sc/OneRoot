import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The questions OneRoot asks: confirmations, names, and what to do about
/// files that already exist. libadwaita dialogs, attached to the window.
@MainActor
enum Dialogs {
    /// Asks and waits for the answer — for the shared core's synchronous
    /// questions (`Platform.confirmTrash` and friends), as NSAlert's
    /// runModal does on the Mac. Runs the main loop until answered.
    static func runModal(_ dialog: AlertDialog, parent: Widget?) -> String {
        var answer: String?
        dialog.onResponse { answer = $0 }
        dialog.present(parent)
        let context = g_main_context_default()
        while answer == nil {
            g_main_context_iteration(context, 1)
        }
        return answer ?? dialog.closeResponse
    }

    static func alert(heading: String, body: String, responses: [(id: String, label: String)],
                      destructive: String? = nil, suggested: String? = nil, defaultResponse: String? = nil) -> AlertDialog {
        let dialog = AlertDialog(heading: heading, body: body)
        for response in responses { dialog.addResponse(response.id, label: response.label) }
        if let destructive { dialog.setResponseAppearance(destructive, appearance: .destructive) }
        if let suggested { dialog.setResponseAppearance(suggested, appearance: .suggested) }
        dialog.defaultResponse = defaultResponse ?? suggested
        dialog.closeResponse = responses.first?.id ?? "cancel"
        return dialog
    }

    /// A notice with an OK button.
    static func showError(_ title: String, _ message: String, parent: Widget?) {
        let dialog = alert(heading: title, body: message, responses: [("ok", "OK")], defaultResponse: "ok")
        dialog.present(parent)
    }

    /// Asks for a name: Rename, New Folder, New File. The part before the
    /// extension is selected, as in every file manager.
    static func promptName(heading: String, body: String? = nil, initial: String, confirm: String,
                           selectsStem: Bool, parent: Widget?, completion: @escaping (String) -> Void) {
        let dialog = alert(heading: heading, body: body ?? "", responses: [("cancel", "Cancel"), ("ok", confirm)], suggested: "ok")
        let entry = Entry()
        entry.text = initial
        entry.activatesDefault = true
        dialog.extraChild = entry
        dialog.setResponseEnabled("ok", enabled: !initial.trimmingCharacters(in: .whitespaces).isEmpty)
        entry.onChanged { [weak entry, weak dialog] in
            guard let entry, let dialog else { return }
            let name = entry.text.trimmingCharacters(in: .whitespaces)
            dialog.setResponseEnabled("ok", enabled: !name.isEmpty && !name.contains("/"))
        }
        dialog.onResponse { [weak entry] response in
            guard response == "ok", let entry else { return }
            let name = entry.text.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            completion(name)
        }
        dialog.present(parent)
        // Once the dialog has focused the entry (which selects it all).
        let stem = (initial as NSString).deletingPathExtension
        let end = selectsStem && !stem.isEmpty && stem != initial ? stem.count : -1
        MainContext.delay(ms: 60) { [weak entry] in
            guard let entry else { return }
            _ = entry.grabFocus()
            gtk_editable_select_region(OpaquePointer(entry.pointer), 0, Int32(end))
        }
    }

    // MARK: Files that already exist

    /// What to do with names already taken at the destination — the same
    /// choice for all, or one per item.
    static func resolveConflicts(_ request: FileConflictRequest, parent: Widget?, completion: @escaping (FileConflictAnswer) -> Void) {
        let conflicts = request.conflicts
        let verb = request.isMove ? "Moving" : "Copying"
        let destination = request.destination.lastPathComponent
        if conflicts.count == 1, let conflict = conflicts.first {
            let heading = "\u{201C}\(conflict.name)\u{201D} Already Exists"
            let body = "\(verb) to \u{201C}\(destination)\u{201D}. " + describe(conflict)
            var responses: [(id: String, label: String)] = [("cancel", "Stop"), ("skip", "Skip"), ("keepBoth", "Keep Both")]
            if conflict.canMerge { responses.append(("merge", "Merge")) }
            responses.append(("replace", "Replace"))
            let dialog = alert(heading: heading, body: body, responses: responses, destructive: "replace", defaultResponse: "keepBoth")
            dialog.preferWideLayout = true
            dialog.onResponse { response in
                switch response {
                case "skip": completion(.all(.skip, for: conflicts))
                case "keepBoth": completion(.all(.keepBoth, for: conflicts))
                case "merge": completion(.all(.merge, for: conflicts))
                case "replace": completion(.all(.replace, for: conflicts))
                default: completion(.cancel)
                }
            }
            dialog.present(parent)
            return
        }

        // Several: a choice per item, with buttons to set them all.
        let heading = "\(conflicts.count) Items Already Exist"
        let body = "\(verb) \(request.itemCount) item\(request.itemCount == 1 ? "" : "s") to \u{201C}\(destination)\u{201D}. Choose what happens to each one that's already there."
        let dialog = alert(heading: heading, body: body, responses: [("cancel", "Stop"), ("apply", "Continue")], suggested: "apply")
        dialog.preferWideLayout = true
        let choices: [(label: String, resolution: FileConflictResolution)] = [
            ("Skip", .skip), ("Keep Both", .keepBoth), ("Replace", .replace), ("Merge", .merge),
        ]
        var dropDowns: [(FileConflictItem, DropDown)] = []
        let list = ListBox()
        list.addCSSClass("boxed-list")
        list.selectionMode = GTK_SELECTION_NONE
        for conflict in conflicts {
            let options = conflict.canMerge ? choices : Array(choices.dropLast())
            let dropDown = DropDown(strings: options.map(\.label))
            dropDown.selected = 0
            dropDown.valign = GTK_ALIGN_CENTER
            let row = ActionRow(title: conflict.name, subtitle: describe(conflict))
            row.subtitleLines = 2
            row.addSuffix(dropDown)
            list.append(row)
            dropDowns.append((conflict, dropDown))
        }
        let setAll = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        setAll.halign = GTK_ALIGN_END
        for (label, index) in [("Skip All", 0), ("Keep Both for All", 1), ("Replace All", 2)] {
            let button = Button(label: label)
            button.addCSSClass(.flat)
            button.onClicked { for (_, dropDown) in dropDowns { dropDown.selected = index } }
            setAll.append(button)
        }
        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.pointer), 320)
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        content.append(setAll)
        content.append(scroller)
        dialog.extraChild = content
        dialog.onResponse { response in
            guard response == "apply" else {
                completion(.cancel)
                return
            }
            var map: [URL: FileConflictResolution] = [:]
            for (conflict, dropDown) in dropDowns {
                let options = conflict.canMerge ? choices : Array(choices.dropLast())
                map[conflict.source] = options[min(max(dropDown.selected, 0), options.count - 1)].resolution
            }
            completion(.resolve(map))
        }
        dialog.present(parent)
    }

    /// "The one being copied is newer (5 Nov 2026, 2 MB); the one there is 1 KB."
    private static func describe(_ conflict: FileConflictItem) -> String {
        func side(_ metadata: FileConflictItem.Metadata) -> String {
            var parts: [String] = []
            if let modified = metadata.modified { parts.append(Formatting.date(modified)) }
            if !metadata.isDirectory, let size = metadata.size { parts.append(Formatting.size(size)) }
            if metadata.isDirectory { parts.append("folder") }
            return parts.joined(separator: ", ")
        }
        let newer: String
        switch conflict.newer {
        case .incoming?: newer = " (newer)"
        default: newer = ""
        }
        let older = conflict.newer == .existing ? " (newer)" : ""
        return "Incoming: \(side(conflict.incoming))\(newer). Already there: \(side(conflict.current))\(older)."
    }

    /// Names the destination's file system can't store (FAT, exFAT, SMB).
    static func resolveNameFixes(_ request: NameFixRequest, parent: Widget?, completion: @escaping (NameFixAnswer) -> Void) {
        let lines = request.fixes.prefix(8).map { "\u{201C}\($0.oldName)\u{201D} → \u{201C}\($0.newName)\u{201D}" }
        let more = request.isTruncated || request.fixes.count > 8 ? "\n…and more" : ""
        let body = "\u{201C}\(request.destination.lastPathComponent)\u{201D} can't store these names. OneRoot can give them names it can store:\n\n" + lines.joined(separator: "\n") + more
        let dialog = alert(heading: "Some Names Won't Fit", body: body,
                           responses: [("cancel", "Stop"), ("skip", "Skip Them"), ("rename", "Rename and Continue")],
                           suggested: "rename")
        dialog.onResponse { response in
            switch response {
            case "rename": completion(.rename)
            case "skip": completion(.skip)
            default: completion(.cancel)
            }
        }
        dialog.present(parent)
    }
}
