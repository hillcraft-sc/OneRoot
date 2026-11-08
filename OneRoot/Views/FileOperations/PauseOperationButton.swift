import SwiftUI

/// Pause / Resume beside Cancel, for operations that can really stop and
/// carry on (`FileOperationProgress.canPause`): copies, moves to another
/// volume, compress and extract. Nothing at all for the rest, rather than
/// a button that couldn't keep its promise.
struct PauseOperationButton: View {
    let operation: FileOperationProgress
    var controlSize: ControlSize = .small

    var body: some View {
        if operation.isWaiting, operation.startNow != nil {
            Button("Start Now") {
                FileOperationProgressCenter.shared.requestStartNow(operation.id)
            }
            .buttonStyle(.bordered)
            .controlSize(controlSize)
            .fixedSize()
            .help("Start now instead of waiting for the other copy to finish")
            .accessibilityLabel("Start \(operation.title) now")
        } else if operation.canPause {
            Button {
                if operation.isPaused {
                    FileOperationProgressCenter.shared.requestResume(operation.id)
                    AccessibilityNotification.Announcement("Resumed \(operation.title)").post()
                } else {
                    FileOperationProgressCenter.shared.requestPause(operation.id)
                    AccessibilityNotification.Announcement("Paused \(operation.title)").post()
                }
            } label: {
                Image(systemName: operation.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(controlSize)
            .fixedSize()
            .help(operation.isPaused ? "Resume" : "Pause; resume to carry on where it stopped")
            .accessibilityLabel(operation.isPaused ? "Resume \(operation.title)" : "Pause \(operation.title)")
        }
    }
}
