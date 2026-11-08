import SwiftUI

/// What clicking a filter chip (or choosing it from Add Filter) opens: the
/// controls for just that condition, presets included. Stays open, so
/// several kinds, extensions, or tags can be ticked in one go.
struct FilterChipEditor: View {
    @Binding var criteria: SearchCriteria
    let field: SearchChip.Field
    let context: SearchChipContext
    var tagSuggestions: [String] = []

    @State private var newTag = ""
    @State private var extensionsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch field {
            case .name, .contents:
                nameEditor
            case .itemType:
                Text("Show").font(.headline)
                Picker("Show:", selection: $criteria.itemType) {
                    ForEach(SearchItemType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            case .kinds:
                Text("Kind").font(.headline)
                ForEach(StorageCategory.allCases.filter { $0 != .other }) { kind in
                    Toggle(isOn: Binding(
                        get: { criteria.kinds.contains(kind) },
                        set: { isOn in
                            if isOn { criteria.kinds.append(kind) } else { criteria.kinds.removeAll { $0 == kind } }
                        }
                    )) {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            case .extensions:
                Text("Extensions").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), alignment: .leading), count: 4), alignment: .leading, spacing: 4) {
                    ForEach(Self.commonExtensions, id: \.self) { ext in
                        Toggle(".\(ext)", isOn: Binding(
                            get: { criteria.extensions.contains(ext) },
                            set: { isOn in
                                if isOn { criteria.extensions.append(ext) } else { criteria.extensions.removeAll { $0 == ext } }
                                extensionsText = criteria.extensions.joined(separator: ", ")
                            }
                        ))
                    }
                }
                TextField("pdf, docx, jpg", text: $extensionsText)
                    .frame(width: 220)
                    .onSubmit(applyExtensions)
                    .onAppear { extensionsText = criteria.extensions.joined(separator: ", ") }
                    .onChange(of: extensionsText) { _, _ in applyExtensions() }
                Text("Separate several with commas.").font(.caption).foregroundStyle(.secondary)
            case .modifiedWithin, .modifiedDates:
                Text("Date Modified").font(.headline)
                Picker("Modified:", selection: dateChoice) {
                    Text("Any Time").tag(DateChoice.any)
                    ForEach(SearchDateRange.allCases) { Text($0.title).tag(DateChoice.range($0)) }
                    Text("Between Dates").tag(DateChoice.between)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if criteria.modifiedAfter != nil || criteria.modifiedBefore != nil {
                    dateRow("After", date: $criteria.modifiedAfter)
                    dateRow("Before", date: $criteria.modifiedBefore)
                }
            case .size:
                Text("Size").font(.headline)
                HStack(spacing: 4) {
                    ForEach(Self.sizePresets, id: \.title) { preset in
                        Button(preset.title) {
                            criteria.minSizeBytes = preset.min
                            criteria.maxSizeBytes = preset.max
                        }
                        .controlSize(.small)
                    }
                }
                sizeRow("At least", bytes: $criteria.minSizeBytes)
                sizeRow("At most", bytes: $criteria.maxSizeBytes)
            case .tag:
                Text("Tags").font(.headline)
                ForEach(tagSuggestions, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { criteria.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } },
                        set: { isOn in
                            criteria.tags = isOn ? TagService.adding(tag, to: criteria.tags) : TagService.removing(tag, from: criteria.tags)
                        }
                    ))
                }
                TextField("Another tag", text: $newTag)
                    .frame(width: 200)
                    .onSubmit {
                        criteria.tags = TagService.adding(newTag, to: criteria.tags)
                        newTag = ""
                    }
                Text("Press Return to add. Items need every tag ticked.").font(.caption).foregroundStyle(.secondary)
            case .includeHidden, .includeCloudStorage:
                EmptyView()
            }
        }
        .frame(minWidth: 220, alignment: .leading)
    }

    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field == .contents ? "Text in Files" : "Name").font(.headline)
            TextField(field == .contents ? "Text to find" : "Name", text: $criteria.pattern)
                .frame(width: 240)
            Picker("Match:", selection: $criteria.patternMode) {
                ForEach(field == .contents ? [SearchPatternMode.contains, .regex] : SearchPatternMode.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .fixedSize()
            if criteria.patternMode == .regex {
                Menu("Regex Suggestions") {
                    ForEach(RegexSuggestion.all) { suggestion in
                        Button(suggestion.name) { criteria.pattern = suggestion.pattern }
                    }
                }
                .fixedSize()
            }
            Toggle("Match case", isOn: $criteria.caseSensitive)
        }
    }

    private enum DateChoice: Hashable {
        case any, range(SearchDateRange), between
    }

    /// The relative ranges and fixed dates as one choice — they'd
    /// contradict each other otherwise.
    private var dateChoice: Binding<DateChoice> {
        Binding(
            get: {
                if let range = criteria.modifiedWithin { return .range(range) }
                if criteria.modifiedAfter != nil || criteria.modifiedBefore != nil { return .between }
                return .any
            },
            set: { choice in
                switch choice {
                case .any:
                    criteria.modifiedWithin = nil
                    criteria.modifiedAfter = nil
                    criteria.modifiedBefore = nil
                case .range(let range):
                    criteria.modifiedWithin = range
                    criteria.modifiedAfter = nil
                    criteria.modifiedBefore = nil
                case .between:
                    criteria.modifiedWithin = nil
                    if criteria.modifiedAfter == nil, criteria.modifiedBefore == nil {
                        let today = Calendar.current.startOfDay(for: Date())
                        criteria.modifiedAfter = Calendar.current.date(byAdding: .day, value: -30, to: today)
                    }
                }
            }
        )
    }

    private static let commonExtensions = ["pdf", "docx", "xlsx", "pptx", "jpg", "png", "heic", "mov", "mp4", "zip", "txt", "md"]

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

    private func applyExtensions() {
        criteria.extensions = extensionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    private func dateRow(_ title: String, date: Binding<Date?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { date.wrappedValue = $0 ? Calendar.current.startOfDay(for: Date()) : nil }
            ))
            .frame(width: 70, alignment: .leading)
            if date.wrappedValue != nil {
                DatePicker("", selection: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    /// Megabytes, decimal — the same units Finder shows sizes in.
    private func sizeRow(_ title: String, bytes: Binding<Int64?>) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            TextField("", value: Binding(
                get: { bytes.wrappedValue.map { Double($0) / 1_000_000 } },
                set: { bytes.wrappedValue = $0.flatMap { $0 > 0 ? Int64($0 * 1_000_000) : nil } }
            ), format: .number.precision(.fractionLength(0...2)))
            .frame(width: 70)
            .accessibilityLabel("\(title), in megabytes")
            Text("MB").foregroundStyle(.secondary)
        }
    }
}
