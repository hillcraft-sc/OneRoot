import AppKit
import SwiftUI

/// The sheet every Quick Action opens first: its options, then a preview
/// of exactly what will be written (and what's skipped, and why) before
/// anything touches the disk. Planning is `QuickActionPlanner`'s; this
/// collects the options and shows the plan.
struct QuickActionSheet: View {
    let onRun: (QuickActionRequest, QuickActionPlan) -> Void
    let onCancel: () -> Void

    @State private var model: QuickActionSheetModel

    private enum ResizeMode: String, CaseIterable, Identifiable {
        case longestSide = "Longest Side"
        case percent = "Percentage"
        var id: Self { self }
    }

    @State private var resizeMode: ResizeMode = .longestSide
    @State private var longestSide = 1600
    @State private var percent = 50
    @State private var quality = 0.85
    @State private var format: ImageFormat
    @State private var combinedName = "Combined"
    @State private var keepLineBreaks = true
    @State private var escapeSymbols = false
    @State private var styledHTML = true

    /// Re-runs the text preview when the options change or loading ends.
    private struct PreviewID: Equatable {
        let request: QuickActionRequest
        let isLoaded: Bool
    }

    init(
        pending: PendingQuickAction,
        onRun: @escaping (QuickActionRequest, QuickActionPlan) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onRun = onRun
        self.onCancel = onCancel
        _model = State(initialValue: QuickActionSheetModel(action: pending.action, urls: pending.urls))
        _format = State(initialValue: ImageTransformService.writableFormats.first ?? .png)
    }

    private var action: QuickAction { model.action }

    var body: some View {
        // Planned once per render: it checks the disk for free names.
        let request = self.request
        let plan = model.plan(request)
        return VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.headline)

            options
            preview(plan)
            if action.isTextConversion { textPreview }

            ForEach(plan.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                HelpButton(topic: .quickActions)
                Text(summary(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(runTitle) { onRun(request, plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isLoading || plan.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580)
        .task { await model.load() }
        .task(id: PreviewID(request: request, isLoaded: !model.isLoading)) {
            guard !model.isLoading else { return }
            await model.loadPreview(request)
        }
    }

    private var heading: String {
        let count = model.urls.count
        switch action {
        case .resizeImages: return count == 1 ? "Resize Image" : "Resize \(count) Images"
        case .convertImages: return count == 1 ? "Convert Image" : "Convert \(count) Images"
        case .removeImageMetadata: return count == 1 ? "Remove Metadata from Image" : "Remove Metadata from \(count) Images"
        case .combineIntoPDF: return "Combine \(count) Items into a PDF"
        case .textToMarkdown: return count == 1 ? "Convert Text to Markdown" : "Convert \(count) Text Files to Markdown"
        case .markdownToHTML: return count == 1 ? "Convert Markdown to HTML" : "Convert \(count) Markdown Files to HTML"
        case .htmlToMarkdown: return count == 1 ? "Convert HTML to Markdown" : "Convert \(count) HTML Files to Markdown"
        case .convertToPDF: return count == 1 ? "Convert Document to PDF" : "Convert \(count) Documents to PDF"
        }
    }

    private var runTitle: String {
        switch action {
        case .resizeImages: return "Resize"
        case .convertImages: return "Convert"
        case .removeImageMetadata: return "Remove Metadata"
        case .combineIntoPDF: return "Combine"
        case .textToMarkdown, .markdownToHTML, .htmlToMarkdown, .convertToPDF: return "Convert"
        }
    }

    private var request: QuickActionRequest {
        switch action {
        case .resizeImages:
            let target: ImageResizeTarget = resizeMode == .longestSide ? .longestSide(longestSide) : .percent(percent)
            return .resize(target, quality: quality)
        case .convertImages:
            return .convert(to: format, quality: quality)
        case .removeImageMetadata:
            return .removeMetadata
        case .combineIntoPDF:
            return .combine(name: QuickActionPlanner.fileName(from: combinedName) ?? "")
        case .textToMarkdown:
            return .textToMarkdown(keepLineBreaks: keepLineBreaks, escapeSymbols: escapeSymbols)
        case .markdownToHTML:
            return .markdownToHTML(styled: styledHTML)
        case .htmlToMarkdown:
            return .htmlToMarkdown
        case .convertToPDF:
            return .convertToPDF
        }
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        switch action {
        case .resizeImages:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Make:")
                    Picker("", selection: $resizeMode) {
                        ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text(resizeMode == .longestSide ? "Longest side:" : "Size:")
                    if resizeMode == .longestSide {
                        HStack {
                            TextField("Pixels", value: $longestSide, format: .number)
                                .frame(width: 80)
                                .accessibilityLabel("Longest side in pixels")
                            Text("pixels").foregroundStyle(.secondary)
                            Menu("Presets") {
                                ForEach([800, 1280, 1600, 2048, 3840], id: \.self) { size in
                                    Button("\(size) pixels") { longestSide = size }
                                }
                            }
                            .fixedSize()
                        }
                    } else {
                        HStack {
                            Slider(value: Binding(get: { Double(percent) }, set: { percent = Int($0) }), in: 5...95, step: 5)
                                .frame(width: 200)
                                .accessibilityLabel("Percentage of the original size")
                            Text("\(percent)%").monospacedDigit()
                        }
                    }
                }
                if model.hasLossyImages {
                    GridRow {
                        Text("Quality:")
                        qualitySlider
                    }
                }
            }
            .onChange(of: longestSide) { _, size in
                if size < 1 { longestSide = 1 }
            }
            Text("Images are never enlarged; ones already that small are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .convertImages:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Format:")
                    Picker("", selection: $format) {
                        ForEach(ImageTransformService.writableFormats) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Format")
                }
                if format.isLossy {
                    GridRow {
                        Text("Quality:")
                        qualitySlider
                    }
                }
            }
        case .removeImageMetadata:
            Text("Makes a copy of each image without the details it carries about where, when, and with what it was taken.")
                .fixedSize(horizontal: false, vertical: true)
        case .combineIntoPDF:
            HStack {
                Text("Name:")
                TextField("PDF name", text: $combinedName)
                Text(".pdf").foregroundStyle(.secondary)
            }
            Text("Pages go in the order below — drag to rearrange, or use the arrows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .textToMarkdown:
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep line breaks", isOn: $keepLineBreaks)
                    .help("On: each line stays its own line. Off: lines join into paragraphs, as Markdown does; blank lines still separate them.")
                Toggle("Show symbols as written", isOn: $escapeSymbols)
                    .help("On: *, #, - and the like stay plain characters. Off: text that already looks like Markdown (“# Title”, “- item”) becomes headings and lists.")
            }
        case .markdownToHTML:
            Toggle("Add simple styling (follows light and dark mode)", isOn: $styledHTML)
        case .htmlToMarkdown:
            EmptyView()
        case .convertToPDF:
            Text("Each document becomes a PDF beside it, on \(Self.paperName) pages.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The first file, converted — what the new file will start with.
    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.urls.count > 1 ? "Preview of the first file" : "Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.preview ?? (model.isLoading ? "" : "Nothing to preview"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .accessibilityLabel("Preview of the converted text")
        }
    }

    /// This Mac's default paper size, as Page Setup has it.
    private static var paperName: String {
        let size = NSPrintInfo.shared.paperSize
        if abs(size.width - 612) < 2, abs(size.height - 792) < 2 { return "US Letter" }
        if abs(size.width - 595) < 2, abs(size.height - 842) < 2 { return "A4" }
        return "\(Int(size.width)) \u{00D7} \(Int(size.height)) point"
    }

    private var qualitySlider: some View {
        HStack {
            Slider(value: $quality, in: 0.3...1, step: 0.05)
                .frame(width: 200)
                .accessibilityLabel("Quality")
                .accessibilityValue("\(Int(quality * 100)) percent")
            Text("\(Int(quality * 100))%").monospacedDigit()
        }
    }

    // MARK: Preview

    private func preview(_ plan: QuickActionPlan) -> some View {
        List {
            ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index, count: plan.items.count)
            }
            .onMove(perform: action == .combineIntoPDF ? { model.move(fromOffsets: $0, toOffset: $1) } : nil)
        }
        .frame(height: action.isTextConversion ? 110 : 220)
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .overlay {
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    private func row(_ item: QuickActionPlanItem, index: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            if action == .combineIntoPDF {
                Text("\(index + 1).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.source.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch item.outcome {
            case .write(let output):
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(output.lastPathComponent)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let note = item.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .include:
                moveButtons(index: index, count: count)
            case .skip(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if action == .combineIntoPDF { moveButtons(index: index, count: count) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func moveButtons(index: Int, count: Int) -> some View {
        HStack(spacing: 2) {
            Button { model.move(at: index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .accessibilityLabel("Move Up")
            Button { model.move(at: index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .accessibilityLabel("Move Down")
        }
        .buttonStyle(.borderless)
    }

    private func summary(_ plan: QuickActionPlan) -> String {
        if model.isLoading { return "Reading\u{2026}" }
        let skipped = plan.items.filter(\.isSkipped).count
        let skippedText = skipped == 0 ? "" : " \u{00B7} \(skipped) skipped"
        if action == .combineIntoPDF {
            guard let output = plan.combinedOutput else {
                return QuickActionPlanner.fileName(from: combinedName) == nil ? "Enter a name for the PDF" : "Nothing to combine"
            }
            let pages = plan.items.compactMap { model.pageCounts[$0.source] }.reduce(0, +)
            return "Makes \u{201C}\(output.lastPathComponent)\u{201D}, \(pages == 1 ? "1 page" : "\(pages) pages")\(skippedText)"
        }
        let made = plan.items.count - skipped
        if made == 0 { return "Nothing to do" }
        return (made == 1 ? "Makes 1 new file beside the original" : "Makes \(made) new files beside the originals") + skippedText
    }
}
