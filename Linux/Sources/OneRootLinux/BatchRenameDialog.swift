import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The batch Rename dialog for several selected items: Replace Text, Add
/// Text, Format (numbering) or Change Case, with a live preview that flags
/// problems (duplicates, clashes, invalid names) before anything is touched.
/// The naming is `BatchRenameService`; this collects the rule and shows its
/// result, as the Mac's BatchRenameView does.
@MainActor
final class BatchRenameDialog {
    private let urls: [URL]
    private let onRename: ([String]) -> Void
    private let service = BatchRenameService()
    private let dialog: AlertDialog

    private let modeDropDown = DropDown(strings: ["Replace Text", "Add Text", "Format", "Change Case"])
    private let findEntry = Entry()
    private let replaceEntry = Entry()
    private let regexCheck = CheckButton(label: "Regular expression")
    private let caseCheck = CheckButton(label: "Case sensitive")
    private let addEntry = Entry()
    private let addPosition = DropDown(strings: ["after name", "before name"])
    private let baseEntry = Entry()
    private let counterPosition = DropDown(strings: ["then number", "number first"])
    private let startSpin = SpinButton(min: 0, max: 1_000_000, step: 1)
    private let digitsSpin = SpinButton(min: 1, max: 6, step: 1)
    private let caseStyleDropDown = DropDown(strings: ["lowercase", "UPPERCASE", "Title Case"])
    private let extensionCheck = CheckButton(label: "Include file extensions")
    private let previewList = ListBox()
    private let summaryLabel = Label("")
    private var panels: [Box] = []
    private var names: [String]

    static func present(urls: [URL], parent: Widget?, onRename: @escaping ([String]) -> Void) {
        let dialog = BatchRenameDialog(urls: urls, onRename: onRename)
        dialog.dialog.present(parent)
        // Held until the dialog is answered.
        dialog.dialog.onResponse { response in
            if response == "rename" { dialog.onRename(dialog.names) }
            withExtendedLifetime(dialog) {}
        }
        MainContext.delay(ms: 60) { _ = dialog.findEntry.grabFocus() }
    }

    private init(urls: [URL], onRename: @escaping ([String]) -> Void) {
        self.urls = urls
        self.onRename = onRename
        names = urls.map(\.lastPathComponent)
        dialog = Dialogs.alert(
            heading: "Rename \(urls.count) Items", body: "",
            responses: [("cancel", "Cancel"), ("rename", "Rename")], suggested: "rename")
        dialog.preferWideLayout = true
        build()
        recompute()
    }

    // MARK: Layout

    private func build() {
        modeDropDown.setAccessibleLabel("Kind of rename")
        func row(_ title: String, _ widgets: [Widget]) -> Box {
            let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            let label = Label(title)
            label.xalign = 0
            label.widthChars = 12
            box.append(label)
            for widget in widgets { box.append(widget) }
            return box
        }
        findEntry.hexpand = true
        findEntry.setAccessibleLabel("Find")
        replaceEntry.hexpand = true
        replaceEntry.setAccessibleLabel("Replace with")
        let options = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 16)
        options.append(regexCheck)
        options.append(caseCheck)
        let replace = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        replace.append(row("Find:", [findEntry]))
        replace.append(row("Replace with:", [replaceEntry]))
        replace.append(options)

        addEntry.hexpand = true
        addEntry.placeholderText = "Text to add"
        addEntry.setAccessibleLabel("Text to add")
        let add = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        add.append(addEntry)
        add.append(addPosition)

        baseEntry.hexpand = true
        baseEntry.text = "Item"
        baseEntry.placeholderText = "Base name (blank for numbers only)"
        baseEntry.setAccessibleLabel("Base name")
        startSpin.digits = 0
        startSpin.value = 1
        startSpin.setAccessibleLabel("Start at")
        digitsSpin.digits = 0
        digitsSpin.value = 1
        digitsSpin.tooltipText = "Pads numbers with leading zeros: 3 digits gives 001, 002, \u{2026}"
        digitsSpin.setAccessibleLabel("Digits")
        let format = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        let formatName = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        formatName.append(baseEntry)
        formatName.append(counterPosition)
        format.append(formatName)
        format.append(row("Start at:", [startSpin, Label("Digits:"), digitsSpin]))

        let casing = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        casing.append(Label("Make names:"))
        casing.append(caseStyleDropDown)
        casing.halign = GTK_ALIGN_START

        panels = [replace, add, format, casing]
        let fields = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        fields.setSizeRequest(height: 90)
        for panel in panels {
            panel.valign = GTK_ALIGN_START
            fields.append(panel)
        }

        previewList.addCSSClass("boxed-list")
        previewList.selectionMode = GTK_SELECTION_NONE
        let scroller = ScrolledWindow(child: previewList)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.setSizeRequest(height: 200)
        scroller.addCSSClass("card")
        extensionCheck.tooltipText = "Off: \u{201C}IMG_1.jpg\u{201D} keeps its \u{201C}.jpg\u{201D} whatever the rule does. On: the rule sees the whole name."

        summaryLabel.xalign = 0
        summaryLabel.wrap = true
        summaryLabel.addCSSClass("caption")

        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        content.append(modeDropDown)
        content.append(fields)
        content.append(extensionCheck)
        content.append(scroller)
        content.append(summaryLabel)
        dialog.extraChild = content

        for entry in [findEntry, replaceEntry, addEntry, baseEntry] {
            entry.activatesDefault = true
            entry.onChanged { [weak self] in self?.recompute() }
        }
        for check in [regexCheck, caseCheck, extensionCheck] { check.onToggled { [weak self] in self?.recompute() } }
        for dropDown in [modeDropDown, addPosition, counterPosition, caseStyleDropDown] {
            dropDown.onSelectedChanged { [weak self] in self?.recompute() }
        }
        for spin in [startSpin, digitsSpin] { spin.onValueChanged { [weak self] in self?.recompute() } }
    }

    // MARK: Result

    private var rule: BatchRenameRule {
        switch modeDropDown.selected {
        case 1:
            return .add(text: addEntry.text, position: addPosition.selected == 1 ? .before : .after)
        case 2:
            return .format(base: baseEntry.text, counterPosition: counterPosition.selected == 1 ? .before : .after,
                           start: startSpin.intValue, digits: max(1, digitsSpin.intValue))
        case 3:
            let styles: [BatchRenameRule.CaseStyle] = [.lowercase, .uppercase, .titleCase]
            return .changeCase(styles[min(max(caseStyleDropDown.selected, 0), 2)])
        default:
            return .replace(find: findEntry.text, with: replaceEntry.text, caseSensitive: caseCheck.active, regex: regexCheck.active)
        }
    }

    /// Recomputes the new names and the preview, and enables Rename only
    /// when something changes and nothing clashes.
    private func recompute() {
        for (index, panel) in panels.enumerated() { panel.visible = index == modeDropDown.selected }
        var problems: [Int: BatchRenameProblem] = [:]
        do {
            names = try service.newNames(for: urls, rule: rule, includeExtension: extensionCheck.active)
            problems = service.problems(for: urls, newNames: names)
        } catch {
            names = urls.map(\.lastPathComponent)
            summaryLabel.text = error.localizedDescription
            summaryLabel.addCSSClass(.error)
            showPreview(problems: [:])
            dialog.setResponseEnabled("rename", enabled: false)
            return
        }
        let changes = zip(urls, names).filter { $0.lastPathComponent != $1 }.count
        showPreview(problems: problems)
        if let first = problems.keys.sorted().first, let problem = problems[first] {
            summaryLabel.text = problems.count == 1 ? problem.message
                : "\(problems.count) items have problems \u{2014} \(problem.message.lowercased())"
            summaryLabel.addCSSClass(.error)
        } else {
            summaryLabel.text = changes == 0 ? "Nothing would change." : changes == 1 ? "1 item will be renamed." : "\(changes) items will be renamed."
            summaryLabel.removeCSSClass(.error)
        }
        dialog.setResponseEnabled("rename", enabled: problems.isEmpty && changes > 0)
    }

    private func showPreview(problems: [Int: BatchRenameProblem]) {
        previewList.removeAll()
        for (index, url) in urls.enumerated() {
            let newName = names.indices.contains(index) ? names[index] : url.lastPathComponent
            let old = Label(url.lastPathComponent)
            old.xalign = 0
            old.hexpand = true
            old.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            old.addCSSClass(.dimLabel)
            let arrow = Image(iconName: "go-next-symbolic")
            let new = Label(newName)
            new.xalign = 0
            new.hexpand = true
            new.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            let problem = problems[index]
            if problem != nil { new.addCSSClass(.error) }
            let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            row.marginStart = 8
            row.marginEnd = 8
            row.marginTop = 4
            row.marginBottom = 4
            row.append(old)
            row.append(arrow)
            row.append(new)
            row.tooltipText = problem?.message
            row.setAccessibleLabel("\(url.lastPathComponent) becomes \(newName)\(problem.map { ", problem: " + $0.message } ?? "")")
            previewList.append(row)
        }
    }
}
