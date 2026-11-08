import SwiftUI

/// Lets any window ask the Help window to show a topic. `Window` scenes
/// can't take a value the way `WindowGroup(for:)` can, and a `WindowGroup`
/// would open a second Help window per request — so the topic goes through
/// here and the one Help window picks it up, open already or not.
@MainActor
@Observable
final class HelpNavigator {
    static let shared = HelpNavigator()

    /// The topic last asked for, until the Help window has shown it.
    var requestedTopic: HelpTopicID?

    func request(_ topic: HelpTopicID) {
        requestedTopic = topic
    }
}

/// The standard round **?** button, opening a Help topic — for dialogs and
/// Settings panes. `compact` is a small borderless glyph instead, for the
/// tool cards' crowded headers.
struct HelpButton: View {
    let topic: HelpTopicID
    var compact = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if compact {
                Button(action: open) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
            } else {
                HelpLink(action: open)
            }
        }
        .help("Help: \(title)")
        .accessibilityLabel("Help: \(title)")
    }

    private var title: String { HelpContent.topic(topic)?.title ?? "OneRoot Help" }

    private func open() {
        HelpNavigator.shared.request(topic)
        openWindow(id: OneRootApp.helpWindowID)
    }
}
