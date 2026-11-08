import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Under the Context Bar while "Show All Files in Subfolders" is on: what is
/// listed, how many (with progress while the walk runs), whether it was cut
/// off, and the way back. Mirrors the Mac's FlatViewBar.
@MainActor
final class FlatViewBar {
    let widget = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 10)
    private let viewModel: FileListViewModel
    private let title = Label("")
    private let count = Label("")
    private let spinner = Spinner()
    private let cutOff = Label("")
    private var watch: ObservationWatch?

    init(viewModel: FileListViewModel) {
        self.viewModel = viewModel
        widget.addCSSClass("oneroot-compare-bar")
        widget.setAccessibleLabel("All files in subfolders")
        widget.visible = false

        title.ellipsize = PANGO_ELLIPSIZE_MIDDLE
        title.xalign = 0
        title.addCSSClass("heading")
        count.addCSSClass(.dimLabel)
        count.addCSSClass("numeric")
        cutOff.addCSSClass("warning")
        cutOff.tooltipText = "Very large folders are cut off here; filter, sort, or go into a subfolder to see the rest"
        let spacer = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        spacer.hexpand = true
        let back = Button(label: "Show Folders")
        back.tooltipText = "Back to this folder\u{2019}s own contents"
        back.onClicked { [weak viewModel] in viewModel?.setShowsAllFilesInSubfolders(false) }

        widget.append(title)
        if let spinner { widget.append(spinner) }
        widget.append(count)
        widget.append(cutOff)
        widget.append(spacer)
        widget.append(back)

        watch = ObservationWatch.watch({
            (viewModel.showsAllFilesInSubfolders, viewModel.isLoading, viewModel.items.count,
             viewModel.flatViewIsTruncated, viewModel.currentDirectory)
        }) { [weak self] _ in self?.update() }
    }

    private func update() {
        let model = viewModel
        widget.visible = model.showsAllFilesInSubfolders
        guard model.showsAllFilesInSubfolders else { return }
        let folder = model.currentDirectory.map { $0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent } ?? ""
        title.text = "All files in \u{201C}\(folder)\u{201D} and its subfolders"
        let number = model.items.count.formatted()
        spinner?.visible = model.isLoading
        if model.isLoading {
            count.text = "\(number) so far\u{2026}"
            cutOff.visible = false
        } else {
            count.text = model.items.count == 1 ? "1 file" : "\(number) files"
            cutOff.text = "(the first \(FileSystemService.flatViewLimit.formatted()))"
            cutOff.visible = model.flatViewIsTruncated
        }
    }
}
