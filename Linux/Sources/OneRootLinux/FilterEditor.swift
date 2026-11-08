import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The controls for one filter condition, changing the list's filter as they
/// are used — kinds, extensions or tags can be ticked in one go.
@MainActor
final class FilterEditor {
    let widget = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
    private let source: FilterSource
    private var isSyncing = false

    private var filter: SearchCriteria {
        get { source.criteria() }
        set { source.update(newValue) }
    }

    init(source: FilterSource, field: SearchChip.Field) {
        self.source = source
        widget.marginStart = 6
        widget.marginEnd = 6
        widget.marginTop = 6
        widget.marginBottom = 6
        widget.setSizeRequest(width: 230)
        switch field {
        case .name, .contents: buildName()
        case .itemType: buildItemType()
        case .kinds: buildKinds()
        case .extensions: buildExtensions()
        case .modifiedWithin, .modifiedDates: buildDate()
        case .size: buildSize()
        case .tag: buildTags()
        case .includeHidden, .includeCloudStorage: break
        }
    }

    private func heading(_ text: String) {
        let label = Label(text)
        label.addCSSClass(.heading)
        label.xalign = 0
        widget.append(label)
    }

    private var syncDateEntries: (() -> Void)?

    private func note(_ text: String) {
        let label = Label(text)
        label.addCSSClass(.dimLabel)
        label.addCSSClass("caption")
        label.xalign = 0
        label.wrap = true
        widget.append(label)
    }

    /// Radio buttons, one per choice; `select` runs when one is picked.
    private func radios(_ titles: [String], selected: Int, select: @escaping (Int) -> Void) {
        var first: CheckButton?
        for (index, title) in titles.enumerated() {
            let button = CheckButton(label: title)
            if let first { button.setGroup(first) } else { first = button }
            button.active = index == selected
            button.onToggled { [weak self, weak button] in
                guard let self, !self.isSyncing, let button, button.active else { return }
                select(index)
            }
            widget.append(button)
        }
    }

    // MARK: Fields

    private func buildName() {
        heading("Name")
        let text = Entry()
        text.text = filter.pattern
        text.placeholderText = "Name"
        text.onChanged { [weak self, weak text] in
            guard let self, let text, self.filter.pattern != text.text else { return }
            self.filter.pattern = text.text
        }
        widget.append(text)
        let modes = SearchPatternMode.allCases
        let dropDown = DropDown(strings: modes.map(\.title))
        dropDown.selected = modes.firstIndex(of: filter.patternMode) ?? 0
        dropDown.onSelectedChanged { [weak self, weak dropDown] in
            guard let self, let dropDown, modes.indices.contains(dropDown.selected) else { return }
            self.filter.patternMode = modes[dropDown.selected]
        }
        widget.append(dropDown)
        let regex = SearchInputHelpers.regexSuggestionsButton { [weak self, weak text] pattern in
            text?.text = pattern
            self?.filter.pattern = pattern
        }
        regex.halign = GTK_ALIGN_START
        regex.visible = filter.patternMode == .regex
        widget.append(regex)
        dropDown.onNotify(.custom("selected")) { [weak self, weak regex] in
            regex?.visible = self?.filter.patternMode == .regex
        }
        let matchCase = CheckButton(label: "Match case")
        matchCase.active = filter.caseSensitive
        matchCase.onToggled { [weak self, weak matchCase] in
            guard let self, let matchCase else { return }
            self.filter.caseSensitive = matchCase.active
        }
        widget.append(matchCase)
    }

    private func buildItemType() {
        heading("Show")
        let types: [SearchItemType] = [.filesAndFolders, .filesOnly, .foldersOnly]
        radios(types.map(\.title), selected: types.firstIndex(of: filter.itemType) ?? 0) { [weak self] index in
            self?.filter.itemType = types[index]
        }
    }

    private func buildKinds() {
        heading("Kind")
        for kind in StorageCategory.allCases where kind != .other {
            let button = CheckButton(label: kind.title)
            button.active = filter.kinds.contains(kind)
            button.onToggled { [weak self, weak button] in
                guard let self, let button else { return }
                if button.active {
                    if !self.filter.kinds.contains(kind) { self.filter.kinds.append(kind) }
                } else {
                    self.filter.kinds.removeAll { $0 == kind }
                }
            }
            widget.append(button)
        }
    }

    private func buildExtensions() {
        heading("Extensions")
        let text = Entry()
        text.text = filter.extensions.joined(separator: ", ")
        text.placeholderText = "pdf, docx, jpg"
        text.onChanged { [weak self, weak text] in
            guard let self, let text else { return }
            let parsed = Self.parseExtensions(text.text)
            if parsed != self.filter.extensions { self.filter.extensions = parsed }
        }
        widget.append(text)
        note("Separate several with commas.")
    }

    /// "pdf, .DOCX" → ["pdf", "docx"].
    static func parseExtensions(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    private func buildDate() {
        heading("Date Modified")
        let ranges = SearchDateRange.allCases
        let selected = filter.modifiedWithin.flatMap { ranges.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let hasDates = filter.modifiedAfter != nil || filter.modifiedBefore != nil
        let betweenIndex = ranges.count + 1
        let fields = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 4)
        fields.visible = hasDates
        radios(["Any Time"] + ranges.map(\.title) + ["Between Dates"], selected: hasDates ? betweenIndex : selected) { [weak self] index in
            guard let self else { return }
            fields.visible = index == betweenIndex
            if index == betweenIndex {
                // Starts from the last 30 days, as the Mac's does.
                self.filter.modifiedWithin = nil
                if self.filter.modifiedAfter == nil, self.filter.modifiedBefore == nil {
                    let today = Calendar.current.startOfDay(for: Date())
                    self.filter.modifiedAfter = Calendar.current.date(byAdding: .day, value: -30, to: today)
                }
                self.syncDateEntries?()
            } else {
                self.filter.modifiedAfter = nil
                self.filter.modifiedBefore = nil
                self.filter.modifiedWithin = index == 0 ? nil : ranges[index - 1]
            }
        }
        func dateRow(_ title: String, get: @escaping () -> Date?, set: @escaping (Date?) -> Void) -> Entry {
            let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
            let label = Label(title)
            label.xalign = 0
            label.widthChars = 6
            let entry = Entry()
            entry.placeholderText = "YYYY-MM-DD"
            entry.text = SearchInputHelpers.formatDate(get())
            entry.hexpand = true
            entry.setAccessibleLabel("\(title) date, year-month-day")
            entry.onChanged { [weak entry] in
                guard let entry else { return }
                let text = entry.text.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { set(nil); entry.removeCSSClass("error") }
                else if let date = SearchInputHelpers.parseDate(text) { set(date); entry.removeCSSClass("error") }
                else { entry.addCSSClass("error") }
            }
            row.append(label)
            row.append(entry)
            fields.append(row)
            return entry
        }
        let from = dateRow("After", get: { [weak self] in self?.filter.modifiedAfter }, set: { [weak self] in self?.filter.modifiedAfter = $0 })
        let to = dateRow("Before", get: { [weak self] in self?.filter.modifiedBefore }, set: { [weak self] in self?.filter.modifiedBefore = $0 })
        syncDateEntries = { [weak self] in
            from.text = SearchInputHelpers.formatDate(self?.filter.modifiedAfter)
            to.text = SearchInputHelpers.formatDate(self?.filter.modifiedBefore)
        }
        let hint = Label("After the first date, up to the start of the second (YYYY-MM-DD).")
        hint.addCSSClass(.dimLabel)
        hint.addCSSClass("caption")
        hint.xalign = 0
        hint.wrap = true
        hint.maxWidthChars = 34
        fields.append(hint)
        widget.append(fields)
    }

    private struct SizePreset {
        let title: String
        let min: Int64?
        let max: Int64?
    }

    private static let sizePresets: [SizePreset] = [
        SizePreset(title: "< 100 KB", min: nil, max: 100_000),
        SizePreset(title: "> 1 MB", min: 1_000_000, max: nil),
        SizePreset(title: "> 10 MB", min: 10_000_000, max: nil),
        SizePreset(title: "> 100 MB", min: 100_000_000, max: nil),
        SizePreset(title: "> 1 GB", min: 1_000_000_000, max: nil),
    ]

    private func buildSize() {
        heading("Size")
        let presets = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        presets.addCSSClass(.linked)
        widget.append(presets)
        let minimum = megabyteRow("At least", bytes: filter.minSizeBytes) { [weak self] in self?.filter.minSizeBytes = $0 }
        let maximum = megabyteRow("At most", bytes: filter.maxSizeBytes) { [weak self] in self?.filter.maxSizeBytes = $0 }
        for preset in Self.sizePresets {
            let button = Button(label: preset.title)
            button.onClicked { [weak self] in
                guard let self else { return }
                self.isSyncing = true
                minimum.value = Double(preset.min ?? 0) / 1_000_000
                maximum.value = Double(preset.max ?? 0) / 1_000_000
                self.isSyncing = false
                self.filter.minSizeBytes = preset.min
                self.filter.maxSizeBytes = preset.max
            }
            presets.append(button)
        }
    }

    /// Megabytes, decimal — the units the size column shows. 0 means unset.
    private func megabyteRow(_ title: String, bytes: Int64?, set: @escaping (Int64?) -> Void) -> SpinButton {
        let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        let label = Label(title)
        label.xalign = 0
        label.widthChars = 8
        let spin = SpinButton(min: 0, max: 1_000_000, step: 1)
        spin.digits = 0
        spin.value = Double(bytes ?? 0) / 1_000_000
        spin.setAccessibleLabel("\(title), in megabytes")
        spin.onValueChanged { [weak self, weak spin] in
            guard let self, !self.isSyncing, let spin else { return }
            set(spin.value > 0 ? Int64(spin.value * 1_000_000) : nil)
        }
        row.append(label)
        row.append(spin)
        row.append(Label("MB"))
        widget.append(row)
        return spin
    }

    private func buildTags() {
        heading("Tags")
        // Chosen tags stay listed (ticked); the folder's other tags follow.
        let others = TagService.suggestions(standard: [], inFolder: source.tagsInFolder(), excluding: filter.tags)
        for tag in filter.tags + others {
            let button = CheckButton(label: tag)
            button.active = filter.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            button.onToggled { [weak self, weak button] in
                guard let self, let button else { return }
                self.filter.tags = button.active
                    ? TagService.adding(tag, to: self.filter.tags)
                    : TagService.removing(tag, from: self.filter.tags)
            }
            widget.append(button)
        }
        let another = Entry()
        another.placeholderText = "Another tag"
        another.onActivate { [weak self, weak another] in
            guard let self, let another, !another.text.isEmpty else { return }
            self.filter.tags = TagService.adding(another.text, to: self.filter.tags)
            another.text = ""
        }
        widget.append(another)
        note("Press Enter to add. Items need every tag ticked.")
    }
}
