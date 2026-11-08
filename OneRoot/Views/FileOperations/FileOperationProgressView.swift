import SwiftUI

/// A Finder-style progress popup for one Copy/Move/Compress/Extract — icon,
/// title, progress bar (determinate or not, see `FileOperationProgress
/// .isIndeterminate`), byte counts/ETA or elapsed time, and a cancel
/// button. One `FileOperationProgressView` window per operation (see the
/// `fileOperationProgress` `WindowGroup` in `OneRootApp`), matching
/// Finder's own behavior of several small stacked copy windows rather than
/// one window with multiple rows.
struct FileOperationProgressView: View {
    let operationID: UUID

    private var center = FileOperationProgressCenter.shared
    @Environment(\.appTheme) private var theme

    private var operation: FileOperationProgress? {
        center.operations.first { $0.id == operationID }
    }

    var body: some View {
        // No self-dismiss logic here on purpose — `RootView` owns
        // open/close entirely (`openWindow`/`dismissWindow`, driven by
        // `FileOperationProgressCenter.operations`'s own diff), since a
        // `.onAppear`-triggered self-dismiss raced `openWindow`'s real
        // window-server round-trip: a fast operation could finish and
        // remove itself before this view's first `.onAppear` ever fired,
        // closing the window before it was ever actually visible.
        Group {
            if let operation {
                content(for: operation)
            } else {
                Color.clear.frame(width: 340, height: 80)
            }
        }
    }

    private func content(for operation: FileOperationProgress) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: operation.symbolName)
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(operation.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    PauseOperationButton(operation: operation)
                    CancelOperationButton(operation: operation)
                }

                if operation.isIndeterminate, !operation.isPaused {
                    ProgressView()
                } else {
                    // Gray and still while paused.
                    ProgressView(value: Double(operation.completedBytes), total: Double(max(operation.totalBytes, 1)))
                        .tint(operation.isPaused ? .secondary : nil)
                }

                TimelineView(.periodic(from: operation.startDate, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FileOperationText.status(for: operation, now: context.date))
                        if let item = FileOperationText.currentItem(for: operation) {
                            Text(item)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let route = FileOperationText.route(source: operation.sourceFolder, destination: operation.destinationFolder) {
                            Text(route)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
