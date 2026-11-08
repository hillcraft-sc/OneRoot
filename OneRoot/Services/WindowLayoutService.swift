import Foundation

/// Remembers the most recently changed window layout, so a new window
/// (⌘N, or a first launch without a saved session) opens with the panes
/// you last chose. Each open window keeps its own layout from then on —
/// see `WindowLayout`.
struct WindowLayoutService {
    private static let key = "com.oneroot.windowLayout"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WindowLayout {
        guard let data = defaults.data(forKey: Self.key),
              let layout = try? JSONDecoder().decode(WindowLayout.self, from: data) else {
            return legacyLayout()
        }
        return layout.clamped
    }

    /// Before the Inspector, the preview pane was one app-wide setting;
    /// its width carries over. (The Inspector is on by default now.)
    private func legacyLayout() -> WindowLayout {
        var layout = WindowLayout()
        if let width = defaults.object(forKey: "com.oneroot.previewPaneWidth") as? Double {
            layout.inspectorWidth = width
        }
        return layout.clamped
    }

    func save(_ layout: WindowLayout) {
        defaults.set(try? JSONEncoder().encode(layout), forKey: Self.key)
    }
}
