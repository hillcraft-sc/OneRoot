import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The sheet for one Quick Action: its few options, a preview of exactly
/// what will be written (new files beside the originals — never over them),
/// the warnings, and Run. The planning and reading are the shared
/// `QuickActionSheetModel`; this collects the options and shows the plan, as
/// the Mac's QuickActionSheet does.
@MainActor
final class QuickActionDialog {
    private let action: QuickAction
    private let model: QuickActionSheetModel
    private let onRun: (QuickActionRequest, QuickActionPlan) -> Void
    private let onCancel: () -> Void
    private let dialog: AlertDialog

    // Options
    private let resizeMode = DropDown(strings: ["Longest side", "Percentage"])
    private static let sides = [640, 800, 1024, 1280, 1600, 1920, 2560, 3840]
    private let sideDropDown = DropDown(strings: QuickActionDialog.sides.map { "\($0) pixels" })
    private let percentSpin = SpinButton(min: 5, max: 95, step: 5)
    private let qualitySpin = SpinButton(min: 30, max: 100, step: 5)
    private let formatDropDown: DropDown
    private let formats: [ImageFormat]
    private let nameEntry = Entry()
    private let lineBreaksCheck = CheckButton(label: "Keep line breaks")
    private let symbolsCheck = CheckButton(label: "Show symbols as written")
    private let styledCheck = CheckButton(label: "Add simple styling (light and dark)")
    private var optionRows: [String: Box] = [:]

    // Results
    private let planList = ListBox()
    private let warningLabel = Label("")
    private let summaryLabel = Label("")
    private let previewLabel = Label("")
    private let previewFrame = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
    private var previewTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var finished = false

    /// Shows the sheet for `pending` over `parent`. It holds itself until
    /// it is answered.
    static func present(_ pending: PendingQuickAction, parent: Widget?, onRun: @escaping (QuickActionRequest, QuickActionPlan) -> Void, onCancel: @escaping () -> Void) {
        let sheet = QuickActionDialog(pending: pending, onRun: onRun, onCancel: onCancel)
        sheet.dialog.present(parent)
        sheet.dialog.onResponse { response in
            sheet.finish(run: response == "run")
            withExtendedLifetime(sheet) {}
        }
        sheet.loadTask = Task { [weak sheet] in
            await sheet?.model.load()
            sheet?.refresh()
        }
    }

    private init(pending: PendingQuickAction, onRun: @escaping (QuickActionRequest, QuickActionPlan) -> Void, onCancel: @escaping () -> Void) {
        action = pending.action
        model = QuickActionSheetModel(action: pending.action, urls: pending.urls)
        self.onRun = onRun
        self.onCancel = onCancel
        let writable = QuickActionServices.current.images.writableFormats
        formats = writable.isEmpty ? [.png] : writable
        formatDropDown = DropDown(strings: formats.map(\.title))
        let count = pending.urls.count
        let subject = count == 1 ? "\u{201C}\(pending.urls[0].lastPathComponent)\u{201D}" : "\(count) Items"
        dialog = Dialogs.alert(
            heading: "\(pending.action.menuTitle.replacingOccurrences(of: "\u{2026}", with: "")): \(subject)",
            body: "New files are written beside the originals; nothing is replaced.",
            responses: [("cancel", "Cancel"), ("run", Self.runTitle(pending.action))], suggested: "run")
        dialog.preferWideLayout = true
        build()
        dialog.setResponseEnabled("run", enabled: false)
        refresh()
    }

    static func runTitle(_ action: QuickAction) -> String {
        switch action {
        case .resizeImages: return "Resize"
        case .convertImages, .textToMarkdown, .markdownToHTML, .htmlToMarkdown, .convertToPDF: return "Convert"
        case .removeImageMetadata: return "Remove Metadata"
        case .combineIntoPDF: return "Combine"
        }
    }

    private func finish(run: Bool) {
        guard !finished else { return }
        finished = true
        previewTask?.cancel()
        loadTask?.cancel()
        if run {
            let request = currentRequest
            onRun(request, model.plan(request))
        } else {
            onCancel()
        }
    }

    // MARK: Layout

    private func row(_ title: String, _ widgets: [Widget]) -> Box {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        let label = Label(title)
        label.xalign = 0
        label.widthChars = 12
        box.append(label)
        for widget in widgets { box.append(widget) }
        return box
    }

    private func build() {
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        content.setSizeRequest(width: 600)

        switch action {
        case .resizeImages:
            sideDropDown.selected = Self.sides.firstIndex(of: 1600) ?? 0
            percentSpin.digits = 0
            percentSpin.value = 50
            resizeMode.setAccessibleLabel("How to size")
            sideDropDown.setAccessibleLabel("Longest side in pixels")
            percentSpin.setAccessibleLabel("Percent of the original size")
            content.append(row("Resize by:", [resizeMode, sideDropDown, percentSpin]))
            content.append(qualityRow())
        case .convertImages:
            formatDropDown.setAccessibleLabel("Convert to")
            content.append(row("Convert to:", [formatDropDown]))
            content.append(qualityRow())
        case .combineIntoPDF:
            nameEntry.text = "Combined"
            nameEntry.hexpand = true
            nameEntry.activatesDefault = true
            nameEntry.setAccessibleLabel("PDF name")
            content.append(row("PDF name:", [nameEntry]))
        case .textToMarkdown:
            lineBreaksCheck.active = true
            content.append(lineBreaksCheck)
            content.append(symbolsCheck)
        case .markdownToHTML:
            styledCheck.active = true
            content.append(styledCheck)
        case .removeImageMetadata, .htmlToMarkdown, .convertToPDF:
            break
        }

        planList.addCSSClass("boxed-list")
        planList.selectionMode = GTK_SELECTION_NONE
        let scroller = ScrolledWindow(child: planList)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.setSizeRequest(height: 190)
        scroller.addCSSClass("card")
        content.append(scroller)

        if action.isTextConversion {
            previewLabel.xalign = 0
            previewLabel.yalign = 0
            previewLabel.wrap = true
            previewLabel.selectable = true
            previewLabel.addCSSClass("monospace")
            previewLabel.addCSSClass("caption")
            previewLabel.setAccessibleLabel("Preview of the first converted file")
            previewLabel.marginStart = 8
            previewLabel.marginEnd = 8
            previewLabel.marginTop = 8
            previewLabel.marginBottom = 8
            let previewScroller = ScrolledWindow(child: previewLabel)
            previewScroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
            previewScroller.setSizeRequest(height: 120)
            previewScroller.addCSSClass("card")
            content.append(previewScroller)
        }

        warningLabel.xalign = 0
        warningLabel.wrap = true
        warningLabel.addCSSClass("caption")
        warningLabel.addCSSClass(.dimLabel)
        summaryLabel.xalign = 0
        summaryLabel.wrap = true
        summaryLabel.addCSSClass("caption")
        content.append(warningLabel)
        content.append(summaryLabel)
        dialog.extraChild = content

        qualitySpin.digits = 0
        qualitySpin.value = 85
        qualitySpin.setAccessibleLabel("Quality in percent")
        for dropDown in [resizeMode, sideDropDown, formatDropDown] { dropDown.onSelectedChanged { [weak self] in self?.refresh() } }
        for spin in [percentSpin, qualitySpin] { spin.onValueChanged { [weak self] in self?.refresh() } }
        nameEntry.onChanged { [weak self] in self?.refresh() }
        for check in [lineBreaksCheck, symbolsCheck, styledCheck] { check.onToggled { [weak self] in self?.refresh() } }
    }

    private func qualityRow() -> Box {
        let box = row("Quality:", [qualitySpin, Label("%")])
        optionRows["quality"] = box
        return box
    }

    // MARK: Request and plan

    private var currentRequest: QuickActionRequest {
        let quality = qualitySpin.value / 100
        switch action {
        case .resizeImages:
            let target: ImageResizeTarget = resizeMode.selected == 1
                ? .percent(percentSpin.intValue)
                : .longestSide(Self.sides[min(max(sideDropDown.selected, 0), Self.sides.count - 1)])
            return .resize(target, quality: quality)
        case .convertImages:
            return .convert(to: formats[min(max(formatDropDown.selected, 0), formats.count - 1)], quality: quality)
        case .removeImageMetadata: return .removeMetadata
        case .combineIntoPDF: return .combine(name: nameEntry.text)
        case .textToMarkdown: return .textToMarkdown(keepLineBreaks: lineBreaksCheck.active, escapeSymbols: symbolsCheck.active)
        case .markdownToHTML: return .markdownToHTML(styled: styledCheck.active)
        case .htmlToMarkdown: return .htmlToMarkdown
        case .convertToPDF: return .convertToPDF
        }
    }

    private func refresh() {
        guard !finished else { return }
        let request = currentRequest
        // Only what applies: the percentage or the side, the quality for
        // lossy output.
        if action == .resizeImages {
            sideDropDown.visible = resizeMode.selected == 0
            percentSpin.visible = resizeMode.selected == 1
        }
        let lossy: Bool
        switch action {
        case .resizeImages: lossy = model.hasLossyImages
        case .convertImages: lossy = formats[min(max(formatDropDown.selected, 0), formats.count - 1)].isLossy
        default: lossy = false
        }
        optionRows["quality"]?.visible = lossy

        if model.isLoading {
            summaryLabel.text = "Reading\u{2026}"
            summaryLabel.removeCSSClass(.error)
            dialog.setResponseEnabled("run", enabled: false)
            showPlan(nil)
            return
        }
        let plan = model.plan(request)
        showPlan(plan)
        warningLabel.text = plan.warnings.joined(separator: "\n")
        warningLabel.visible = !plan.warnings.isEmpty

        let doing = plan.items.filter { !$0.isSkipped }.count
        if action == .combineIntoPDF, !plan.items.isEmpty, plan.combinedOutput == nil, doing > 0 {
            summaryLabel.text = "Give the PDF a name that is a valid file name."
            summaryLabel.addCSSClass(.error)
        } else if plan.isEmpty {
            summaryLabel.text = "Nothing to do for this selection."
            summaryLabel.addCSSClass(.error)
        } else {
            let skipped = plan.items.count - doing
            summaryLabel.text = (action == .combineIntoPDF ? "\(doing) \(doing == 1 ? "item" : "items") into one PDF." : "\(doing) \(doing == 1 ? "file" : "files") will be written.")
                + (skipped > 0 ? " \(skipped) skipped." : "")
            summaryLabel.removeCSSClass(.error)
        }
        dialog.setResponseEnabled("run", enabled: !plan.isEmpty && !(action == .combineIntoPDF && plan.combinedOutput == nil))
        if action.isTextConversion { updatePreview(request) }
    }

    private func updatePreview(_ request: QuickActionRequest) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            await self?.model.loadPreview(request)
            guard let self, !Task.isCancelled else { return }
            let text = self.model.preview ?? ""
            self.previewLabel.text = text.isEmpty ? "(Nothing to preview)" : String(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(30).joined(separator: "\n"))
        }
    }

    // MARK: Plan rows

    private func showPlan(_ plan: QuickActionPlan?) {
        planList.removeAll()
        guard let plan else { return }
        for (index, item) in plan.items.enumerated() {
            let source = Label(item.source.lastPathComponent)
            source.xalign = 0
            source.hexpand = true
            source.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            let detail = Label(item.detail)
            detail.addCSSClass(.dimLabel)
            detail.addCSSClass("caption")
            let result = Label("")
            result.xalign = 0
            result.ellipsize = PANGO_ELLIPSIZE_END
            result.hexpand = true
            switch item.outcome {
            case .write(let url):
                result.text = "\u{2192} \(url.lastPathComponent)" + (item.note.map { " (\($0))" } ?? "")
            case .include:
                result.text = "included" + (item.note.map { " (\($0))" } ?? "")
            case .skip(let reason):
                result.text = "Skipped: \(reason)"
                result.addCSSClass(.dimLabel)
            }
            let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
            row.marginStart = 8
            row.marginEnd = 8
            row.marginTop = 4
            row.marginBottom = 4
            row.append(source)
            row.append(detail)
            row.append(result)
            if action == .combineIntoPDF {
                let up = Button(iconName: "go-up-symbolic")
                let down = Button(iconName: "go-down-symbolic")
                for (button, offset, label) in [(up, -1, "Move up"), (down, 1, "Move down")] {
                    button.addCSSClass(.flat)
                    button.setAccessibleLabel("\(label): \(item.source.lastPathComponent)")
                    button.tooltipText = label
                    button.onClicked { [weak self] in
                        self?.model.move(at: index, by: offset)
                        self?.refresh()
                    }
                    row.append(button)
                }
                up.sensitive = index > 0
                down.sensitive = index < plan.items.count - 1
            }
            row.setAccessibleLabel("\(item.source.lastPathComponent): \(item.detail)")
            planList.append(row)
        }
    }
}
