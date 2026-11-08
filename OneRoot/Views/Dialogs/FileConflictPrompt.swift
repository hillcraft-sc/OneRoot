import SwiftUI

extension View {
    /// Asks about a copy/move's name collisions: the familiar Replace /
    /// Keep Both / Skip alert for one, `FileConflictSheet` for several.
    /// `answer` gets the request's id so a stale dismissal can't answer
    /// the next request in line.
    func fileConflictPrompt(
        _ request: FileConflictRequest?,
        answer: @escaping (FileConflictAnswer, UUID) -> Void
    ) -> some View {
        modifier(FileConflictPrompt(request: request, answer: answer))
    }
}

private struct FileConflictPrompt: ViewModifier {
    let request: FileConflictRequest?
    let answer: (FileConflictAnswer, UUID) -> Void

    private var single: FileConflictRequest? { request.flatMap { $0.conflicts.count == 1 ? $0 : nil } }
    private var several: FileConflictRequest? { request.flatMap { $0.conflicts.count > 1 ? $0 : nil } }

    func body(content: Content) -> some View {
        content
            .alert(
                "\u{201C}\(single?.conflicts.first?.name ?? "")\u{201D} already exists here",
                isPresented: Binding(
                    get: { single != nil },
                    set: { isPresented in
                        if !isPresented, let single { answer(.resolve([:]), single.id) } // dismissed: skip
                    }
                ),
                presenting: single,
                actions: { request in
                    let conflicts = request.conflicts
                    // For two folders Merge comes first: it keeps everything,
                    // where Replace would trash the whole existing folder.
                    if conflicts.first?.canMerge == true {
                        Button("Merge") { answer(.all(.merge, for: conflicts), request.id) }
                    }
                    Button("Replace") { answer(.all(.replace, for: conflicts), request.id) }
                    Button("Keep Both") { answer(.all(.keepBoth, for: conflicts), request.id) }
                    Button("Skip", role: .cancel) { answer(.all(.skip, for: conflicts), request.id) }
                },
                message: { request in
                    if request.conflicts.first?.canMerge == true {
                        Text("Merge adds this folder\u{2019}s contents to the existing one and asks about anything with the same name. Replace moves the existing folder to the Trash.")
                    } else {
                        Text("Replace moves the existing item to the Trash.")
                    }
                }
            )
            .sheet(
                item: Binding(
                    get: { several },
                    set: { newValue in
                        if newValue == nil, let several { answer(.cancel, several.id) }
                    }
                )
            ) { request in
                FileConflictSheet(request: request) { answer($0, request.id) }
            }
    }
}

/// One question for every collision in a copy/move: the same choice for
/// all of them, or — under Choose for Each — a choice per item, with both
/// versions' dates and sizes side by side.
struct FileConflictSheet: View {
    let request: FileConflictRequest
    let onAnswer: (FileConflictAnswer) -> Void

    @State private var choosingEach: Bool
    /// Under Choose for Each. Starts at Skip, so only what the user picks
    /// gets replaced.
    @State private var choices: [URL: FileConflictResolution] = [:]

    init(request: FileConflictRequest, choosingEach: Bool = false, onAnswer: @escaping (FileConflictAnswer) -> Void) {
        self.request = request
        self.onAnswer = onAnswer
        _choosingEach = State(initialValue: choosingEach)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(anyFolders
                         ? "Merge adds a folder\u{2019}s contents to the existing one. Replace moves the existing items to the Trash, so you can get them back."
                         : "Replace moves the existing items to the Trash, so you can get them back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if choosingEach {
                setAllRow
                list
            }

            HStack {
                HelpButton(topic: .fileOperations)
                if choosingEach {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { onAnswer(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .help("Copy nothing")
                if choosingEach {
                    Button(request.isMove ? "Move" : "Copy") { onAnswer(.resolve(currentChoices)) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Choose for Each\u{2026}") { choosingEach = true }
                    if allFolders {
                        Button("Merge All") { onAnswer(.all(.merge, for: request.conflicts)) }
                            .help("Add each folder\u{2019}s contents to the existing one; you\u{2019}ll be asked about anything inside with the same name")
                    }
                    Button("Skip All") { onAnswer(.all(.skip, for: request.conflicts)) }
                        .help("Leave the existing items; \(request.isMove ? "move" : "copy") only the rest")
                    Button("Keep Both") { onAnswer(.all(.keepBoth, for: request.conflicts)) }
                        .help("Give the new items numbered names, like \u{201C}name (2)\u{201D}")
                    Button("Replace All") { onAnswer(.all(.replace, for: request.conflicts)) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: choosingEach ? 680 : (allFolders ? 660 : 560))
    }

    /// Every conflict is folder against folder, so Merge All applies.
    private var allFolders: Bool { request.conflicts.allSatisfy(\.canMerge) }

    private var anyFolders: Bool { request.conflicts.contains(where: \.canMerge) }

    private var title: String {
        let destination = FileManager.default.displayName(atPath: request.destination.path)
        let count = request.conflicts.count
        return count == request.itemCount
            ? "All \(count) items already exist in \u{201C}\(destination)\u{201D}"
            : "\(count) of \(request.itemCount) items already exist in \u{201C}\(destination)\u{201D}"
    }

    private var currentChoices: [URL: FileConflictResolution] {
        Dictionary(uniqueKeysWithValues: request.conflicts.map { ($0.source, choices[$0.source] ?? .skip) })
    }

    private var summary: String {
        let values = currentChoices.values
        let replace = values.filter { $0 == .replace }.count
        let keep = values.filter { $0 == .keepBoth }.count
        let skip = values.filter { $0 == .skip }.count
        let merge = values.filter { $0 == .merge }.count
        let counts = "Replace \(replace) \u{00B7} Keep Both \(keep) \u{00B7} Skip \(skip)"
        return anyFolders ? "Merge \(merge) \u{00B7} " + counts : counts
    }

    private var setAllRow: some View {
        HStack(spacing: 8) {
            Text("Set all to:")
                .foregroundStyle(.secondary)
            if anyFolders {
                Button(allFolders ? "Merge" : "Merge Folders") {
                    for conflict in request.conflicts where conflict.canMerge { choices[conflict.source] = .merge }
                }
                .help("Merge every folder into the existing one")
            }
            Button("Replace") { setAll(.replace) }
            Button("Keep Both") { setAll(.keepBoth) }
            Button("Skip") { setAll(.skip) }
            Button("Replace Older") {
                for conflict in request.conflicts {
                    choices[conflict.source] = conflict.newer == .incoming ? .replace : .skip
                }
            }
            .help("Replace only the existing items that are older than the ones being \(request.isMove ? "moved" : "copied"); skip the rest")
        }
        .controlSize(.small)
    }

    private func setAll(_ resolution: FileConflictResolution) {
        for conflict in request.conflicts { choices[conflict.source] = resolution }
    }

    private var list: some View {
        List(request.conflicts) { conflict in
            HStack(spacing: 10) {
                Image(systemName: conflict.incoming.isDirectory ? "folder" : "doc")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 0) {
                        detailRow("Existing:", conflict.current, isNewer: conflict.newer == .existing)
                        detailRow(request.isMove ? "Moving:" : "Copying:", conflict.incoming, isNewer: conflict.newer == .incoming)
                    }
                    .font(.caption)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Picker("Action for \(conflict.name)", selection: choice(for: conflict)) {
                    if conflict.canMerge {
                        Text("Merge").tag(FileConflictResolution.merge)
                    }
                    Text("Replace").tag(FileConflictResolution.replace)
                    Text("Keep Both").tag(FileConflictResolution.keepBoth)
                    Text("Skip").tag(FileConflictResolution.skip)
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.vertical, 2)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: min(CGFloat(request.conflicts.count) * 58 + 8, 340))
    }

    private func detailRow(_ label: String, _ metadata: FileConflictItem.Metadata, isNewer: Bool) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(describe(metadata))
                    .foregroundStyle(.secondary)
                if isNewer {
                    Text("Newer")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func describe(_ metadata: FileConflictItem.Metadata) -> String {
        var parts: [String] = []
        if let modified = metadata.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        if metadata.isDirectory {
            parts.append("Folder")
        } else if let size = metadata.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? "\u{2014}" : parts.joined(separator: " \u{00B7} ")
    }

    private func choice(for conflict: FileConflictItem) -> Binding<FileConflictResolution> {
        Binding(
            get: { choices[conflict.source] ?? .skip },
            set: { choices[conflict.source] = $0 }
        )
    }
}
