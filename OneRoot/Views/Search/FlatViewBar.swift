import SwiftUI

/// Under the Context Bar while the flat view (View ▸ Show All Files in
/// Subfolders) is on: what's being shown, how many, and the way back.
struct FlatViewBar: View {
    var viewModel: FileListViewModel

    private var folderName: String {
        viewModel.currentDirectory.map { FileManager.default.displayName(atPath: $0.path) } ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("All files in \u{201C}\(folderName)\u{201D} and its subfolders")
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
                Text("\(viewModel.items.count.formatted()) so far\u{2026}")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(viewModel.items.count == 1 ? "1 file" : "\(viewModel.items.count.formatted()) files")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if viewModel.flatViewIsTruncated {
                    Text("(the first \(FileSystemService.flatViewLimit.formatted()))")
                        .foregroundStyle(.orange)
                        .help("Very large folders are cut off here; filter, sort, or go into a subfolder to see the rest")
                }
            }
            Spacer()
            Button {
                viewModel.setShowsAllFilesInSubfolders(false)
            } label: {
                Label("Show Folders", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Back to this folder's own contents")
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All files in subfolders")
    }
}
