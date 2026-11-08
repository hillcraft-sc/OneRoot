import SwiftUI

extension View {
    /// Asks about names the destination can't store (#70).
    func nameFixPrompt(_ request: NameFixRequest?, answer: @escaping (NameFixAnswer, UUID) -> Void) -> some View {
        sheet(item: Binding(
            get: { request },
            set: { newValue in
                if newValue == nil, let request { answer(.cancel, request.id) }
            }
        )) { request in
            NameFixSheet(request: request) { answer($0, request.id) }
        }
    }
}

/// "3 items have names “NO NAME” can't use": each old name → the name it
/// would get, then Rename Copies (default), Skip These, or Cancel.
struct NameFixSheet: View {
    let request: NameFixRequest
    let onAnswer: (NameFixAnswer) -> Void

    private var destinationName: String {
        FileManager.default.displayName(atPath: request.destination.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.fixes.count == 1
                         ? "1 item has a name \u{201C}\(destinationName)\u{201D} can\u{2019}t use"
                         : "\(request.fixes.count.formatted())\(request.isTruncated ? "+" : "") items have names \u{201C}\(destinationName)\u{201D} can\u{2019}t use")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Windows-style drives and shares don\u{2019}t allow \\ : * ? \" < > | in names, names ending in a space or period, or names like CON and NUL. Copying them as they are would stop partway through.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            List(request.fixes) { fix in
                HStack(spacing: 6) {
                    Text(fix.oldName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(fix.newName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help(fix.source.path)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(fix.oldName) becomes \(fix.newName)")
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: min(CGFloat(request.fixes.count) * 24 + 8, 240))

            if request.isTruncated {
                Text("Only the first \(NameCompatibility.limit.formatted()) are listed; any more would still stop the copy.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                HelpButton(topic: .fileOperations)
                Spacer()
                Button("Cancel", role: .cancel) { onAnswer(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button("Skip These") { onAnswer(.skip) }
                    .help("\(request.isMove ? "Move" : "Copy") everything else and leave these where they are")
                Button(request.isMove ? "Rename and Move" : "Rename Copies") { onAnswer(.rename) }
                    .keyboardShortcut(.defaultAction)
                    .help(request.isMove ? "Move them under the new names" : "Give the copies the new names; the originals keep theirs")
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
