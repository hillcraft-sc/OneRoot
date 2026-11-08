import SwiftUI

/// A real, red Cancel button for a running operation — in the File
/// Operations card and the floating progress window. Once pressed it turns
/// into "Cancelling…" with a spinner and can't be pressed again, so it's
/// clear the click was taken while the current item winds down; VoiceOver
/// says so too.
struct CancelOperationButton: View {
    let operation: FileOperationProgress
    var controlSize: ControlSize = .small

    var body: some View {
        if operation.isCancelling {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Cancelling\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cancelling \(operation.title)")
        } else {
            Button(role: .destructive) {
                FileOperationProgressCenter.shared.requestCancel(operation.id)
                AccessibilityNotification.Announcement("Cancelling \(operation.title)").post()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(controlSize)
            .fixedSize()
            .help("Stop this operation; what's done so far stays (and can be undone)")
            .accessibilityLabel("Cancel \(operation.title)")
        }
    }
}
