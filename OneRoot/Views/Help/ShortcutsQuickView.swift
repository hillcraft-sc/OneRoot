import SwiftUI

/// A ⌘B popover cheat-sheet of every shortcut, for a quick glance without
/// leaving the window the way opening the full Help window (⌘?) would.
/// Content is `KeyboardShortcutReference.sections`, the same data the Help
/// window's "Keyboard Shortcuts" topic renders flattened — laid out here as
/// three columns of sections instead, wide rather than tall, so the whole
/// list fits without scrolling.
struct ShortcutsQuickView: View {
    /// Sections grouped into columns by row count, not just split down the
    /// middle, so all three columns end up roughly the same height.
    private static let columns: [[KeyboardShortcutReference.Section]] = {
        let all = KeyboardShortcutReference.sections
        return [
            [all[0], all[1]], // Tabs & Windows, Navigation
            [all[2], all[3]], // Sidebar & Volumes, File List
            [all[4], all[5]], // File Operations, General
        ]
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            ForEach(Array(Self.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(column, id: \.title) { section in
                        SectionView(section: section)
                    }
                }
                .frame(width: 280, alignment: .leading)
            }
        }
        .padding(24)
    }
}

private struct SectionView: View {
    let section: KeyboardShortcutReference.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(section.shortcuts.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.0)
                            .font(.system(.body, design: .monospaced))
                            .kerning(1.5)
                            .foregroundStyle(.secondary)
                        Text(row.1)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

#Preview {
    ShortcutsQuickView()
}
