import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The strip above the two panes while Compare Panes is on: progress while
/// comparing, then what differs on each side, Differences Only, and Copy to
/// Left / Right (each previewed first). Mirrors the Mac's PaneComparisonBar.
@MainActor
final class CompareBar {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 4)
    private let comparison: PaneComparison
    private let parent: () -> Widget?
    private var watches: [ObservationWatch] = []
    private var showsPreview = false

    init(comparison: PaneComparison, parent: @escaping () -> Widget?) {
        self.comparison = comparison
        self.parent = parent
        widget.addCSSClass("oneroot-compare-bar")
        widget.setAccessibleLabel("Compare Panes")
        watches.append(ObservationWatch.watch({ comparison.state }) { [weak self] _ in self?.rebuild() })
        watches.append(ObservationWatch.watch({ comparison.pendingSync?.id }) { [weak self] _ in self?.showPreviewIfNeeded() })
    }

    private func name(_ url: URL) -> String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    private func button(_ title: String, tooltip: String? = nil, _ action: @escaping @MainActor () -> Void) -> Button {
        let button = Button(label: title)
        button.tooltipText = tooltip
        button.onClicked(action)
        return button
    }

    private func label(_ text: String, dim: Bool = false, css: String? = nil) -> Label {
        let label = Label(text)
        if dim { label.addCSSClass(.dimLabel) }
        if let css { label.addCSSClass(css) }
        return label
    }

    private func spacer() -> Widget {
        let box = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        box.hexpand = true
        return box
    }

    private func rebuild() {
        while let child = widget.firstChild { widget.remove(child) }
        let main = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        widget.append(main)
        let comparison = self.comparison
        switch comparison.state {
        case .comparing(let scanned):
            // AdwSpinner spins by itself.
            if let spinner = Spinner() { main.append(spinner) }
            main.append(label(ComparisonText.progress(scanned: scanned), dim: true))
            main.append(spacer())
            main.append(button("Cancel") { comparison.end() })
        case .failed(let message):
            main.append(Image(iconName: "dialog-warning-symbolic"))
            main.append(label(message))
            main.append(spacer())
            main.append(button("Compare Again") { comparison.start() })
            main.append(button("Done") { comparison.end() })
        case .done(let result):
            if result.isIdentical {
                main.append(Image(iconName: "emblem-ok-symbolic"))
                main.append(label("The folders match"))
            } else {
                let sides = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
                for (index, onLeft) in [true, false].enumerated() {
                    if index == 1 { sides.append(Separator(orientation: GTK_ORIENTATION_VERTICAL)) }
                    let side = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
                    let folder = label("\u{201C}\(name(onLeft ? comparison.leftURL : comparison.rightURL))\u{201D}:")
                    folder.ellipsize = PANGO_ELLIPSIZE_MIDDLE
                    folder.maxWidthChars = 24
                    folder.widthChars = 6
                    side.append(folder)
                    side.append(label(ComparisonText.summary(result, onLeft: onLeft), dim: true))
                    sides.append(side)
                }
                if result.unreadableCount > 0 {
                    sides.append(label("\(result.unreadableCount) unreadable", css: "oneroot-cmp-differs"))
                }
                sides.setAccessibleLabel("Differences")
                main.append(sides)
            }
            let actions = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            actions.append(spacer())
            widget.append(actions)
            if !result.isIdentical {
                let only = CheckButton(label: "Differences Only")
                only.active = comparison.showsOnlyDifferences
                only.onToggled { [weak only] in
                    if let only { comparison.showsOnlyDifferences = only.active }
                }
                actions.append(only)
                actions.append(button("\u{2190} Copy to Left", tooltip: "Copy what\u{2019}s newer or missing from \u{201C}\(name(comparison.rightURL))\u{201D} into \u{201C}\(name(comparison.leftURL))\u{201D}") { comparison.planSync(toRight: false) })
                actions.append(button("Copy to Right \u{2192}", tooltip: "Copy what\u{2019}s newer or missing from \u{201C}\(name(comparison.leftURL))\u{201D} into \u{201C}\(name(comparison.rightURL))\u{201D}") { comparison.planSync(toRight: true) })
            }
            let again = Button(iconName: "view-refresh-symbolic")
            again.tooltipText = "Compare Again"
            again.setAccessibleLabel("Compare Again")
            again.onClicked { comparison.start() }
            actions.append(again)
            actions.append(button("Done") { comparison.end() })
        }
    }

    /// The preview before anything is copied.
    private func showPreviewIfNeeded() {
        guard let plan = comparison.pendingSync, !showsPreview else { return }
        showsPreview = true
        let source = name(plan.toRight ? comparison.leftURL : comparison.rightURL)
        let text = ComparisonText.syncPreview(plan, sourceName: source, destinationName: name(plan.destination))
        let responses: [(id: String, label: String)] = plan.items.isEmpty
            ? [("cancel", "OK")]
            : [("cancel", "Cancel"), ("copy", "Copy")]
        let dialog = Dialogs.alert(heading: text.heading, body: text.body, responses: responses,
                                   suggested: plan.items.isEmpty ? nil : "copy", defaultResponse: plan.items.isEmpty ? "cancel" : "copy")
        dialog.onResponse { [weak self] response in
            guard let self else { return }
            self.showsPreview = false
            if response == "copy" { self.comparison.performSync(plan) } else { self.comparison.pendingSync = nil }
        }
        dialog.present(parent())
    }
}
