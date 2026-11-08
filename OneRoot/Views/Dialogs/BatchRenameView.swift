import SwiftUI

/// The batch Rename dialog for several selected items — Finder's Rename
/// dialog plus regex and case changes, with a live preview that flags
/// problems (duplicates, clashes, invalid names) before anything is touched.
/// All the naming logic is `BatchRenameService`; this just collects the
/// rule and shows its result.
struct BatchRenameView: View {
    let urls: [URL]
    let onRename: (_ newNames: [String]) -> Void
    let onCancel: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case replace = "Replace Text"
        case add = "Add Text"
        case format = "Format"
        case changeCase = "Change Case"
        var id: Self { self }
    }

    @State private var mode: Mode = .replace
    @State private var find = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var addText = ""
    @State private var addPosition: BatchRenameRule.Position = .after
    @State private var formatBase = "Item"
    @State private var counterPosition: BatchRenameRule.Position = .after
    @State private var startNumber = 1
    @State private var digits = 1
    @State private var caseStyle: BatchRenameRule.CaseStyle = .lowercase
    @State private var includeExtension = false

    private let service = BatchRenameService()

    var body: some View {
        // Computed once per render and handed down: checking for clashes
        // touches the disk, so it mustn't run once per preview row.
        let result = computeResult()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Rename \(urls.count) Items")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ruleFields
                .frame(minHeight: 60, alignment: .top)

            Toggle("Include file extensions", isOn: $includeExtension)
                .help("Off: “IMG_1.jpg” keeps its “.jpg” whatever the rule does. On: the rule sees the whole name.")

            preview(result)

            HStack {
                HelpButton(topic: .fileOperations)
                Text(summary(result))
                    .font(.caption)
                    .foregroundStyle(result.problems.isEmpty && result.error == nil ? Color.secondary : Color.red)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { onRename(result.names) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename(result))
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private var ruleFields: some View {
        switch mode {
        case .replace:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Find:")
                    TextField(useRegex ? "Regular expression" : "Text", text: $find)
                }
                GridRow {
                    Text("Replace with:")
                    TextField(useRegex ? "Replacement — $1, $2 for groups" : "Text", text: $replacement)
                }
                GridRow {
                    Color.clear.frame(width: 0, height: 0)
                    HStack {
                        Toggle("Regular expression", isOn: $useRegex)
                        Toggle("Case sensitive", isOn: $caseSensitive)
                    }
                }
            }
        case .add:
            HStack {
                TextField("Text to add", text: $addText)
                Picker("", selection: $addPosition) {
                    Text("after name").tag(BatchRenameRule.Position.after)
                    Text("before name").tag(BatchRenameRule.Position.before)
                }
                .labelsHidden()
                .fixedSize()
            }
        case .format:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Name:")
                    HStack {
                        TextField("Base name (blank for numbers only)", text: $formatBase)
                        Picker("", selection: $counterPosition) {
                            Text("then number").tag(BatchRenameRule.Position.after)
                            Text("number first").tag(BatchRenameRule.Position.before)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                GridRow {
                    Text("Start at:")
                    HStack {
                        TextField("", value: $startNumber, format: .number)
                            .frame(width: 70)
                        Stepper("Digits: \(digits)", value: $digits, in: 1...6)
                            .help("Pads numbers with leading zeros: 3 digits gives 001, 002, …")
                    }
                }
            }
        case .changeCase:
            Picker("Make names:", selection: $caseStyle) {
                Text("lowercase").tag(BatchRenameRule.CaseStyle.lowercase)
                Text("UPPERCASE").tag(BatchRenameRule.CaseStyle.uppercase)
                Text("Title Case").tag(BatchRenameRule.CaseStyle.titleCase)
            }
            .pickerStyle(.radioGroup)
        }
    }

    private func preview(_ result: RenameResult) -> some View {
        List(Array(urls.enumerated()), id: \.offset) { index, url in
            let newName = result.names.indices.contains(index) ? result.names[index] : url.lastPathComponent
            let problem = result.problems[index]
            HStack(spacing: 6) {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                Text(newName)
                    .fontWeight(newName == url.lastPathComponent ? .regular : .medium)
                    .foregroundStyle(problem == nil ? Color.primary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(problem?.message ?? "")
            }
        }
        .frame(height: 220)
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }

    // MARK: Result

    private var rule: BatchRenameRule {
        switch mode {
        case .replace: return .replace(find: find, with: replacement, caseSensitive: caseSensitive, regex: useRegex)
        case .add: return .add(text: addText, position: addPosition)
        case .format: return .format(base: formatBase, counterPosition: counterPosition, start: startNumber, digits: digits)
        case .changeCase: return .changeCase(caseStyle)
        }
    }

    private struct RenameResult {
        var names: [String]
        var problems: [Int: BatchRenameProblem]
        var error: String?
        var changeCount: Int
    }

    private func computeResult() -> RenameResult {
        do {
            let names = try service.newNames(for: urls, rule: rule, includeExtension: includeExtension)
            let changes = zip(urls, names).filter { $0.lastPathComponent != $1 }.count
            return RenameResult(names: names, problems: service.problems(for: urls, newNames: names), error: nil, changeCount: changes)
        } catch {
            return RenameResult(names: urls.map(\.lastPathComponent), problems: [:], error: error.localizedDescription, changeCount: 0)
        }
    }

    private func canRename(_ result: RenameResult) -> Bool {
        result.error == nil && result.problems.isEmpty && result.changeCount > 0
    }

    private func summary(_ result: RenameResult) -> String {
        if let error = result.error { return error }
        switch result.problems.count {
        case 0: break
        case 1: return "1 name has a problem (shown in red)"
        default: return "\(result.problems.count) names have problems (shown in red)"
        }
        switch result.changeCount {
        case 0: return "No names change yet"
        case 1: return "1 item will be renamed"
        default: return "\(result.changeCount) items will be renamed"
        }
    }
}
