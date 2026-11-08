import SwiftUI

/// Settings ▸ Appearance: pick a theme. Each row previews the theme with a
/// tiny mock-up of the window in its own colors.
struct AppearanceSettingsView: View {
    private var store = ThemeStore.shared

    /// The families in the order `ThemeCatalog.all` lists them.
    private var families: [(name: String, themes: [Theme])] {
        var order: [String] = []
        for theme in ThemeCatalog.all where !order.contains(theme.family) { order.append(theme.family) }
        return order.map { family in (family, ThemeCatalog.all.filter { $0.family == family }) }
    }

    var body: some View {
        Form {
            Section {
                row(
                    title: "OneRoot (Automatic)",
                    detail: "The OneRoot look — light or dark, following your Mac. The default.",
                    isSelected: store.choiceID == ThemeCatalog.automaticChoiceID,
                    swatches: [ThemeCatalog.oneRootLight, ThemeCatalog.oneRootDark]
                ) { store.choose(ThemeCatalog.automaticChoiceID) }
                row(
                    title: "macOS (Automatic)",
                    detail: "Plain macOS colors with burgundy folders — light or dark, following your Mac",
                    isSelected: store.choiceID == ThemeCatalog.nativeAutomaticChoiceID,
                    swatches: [ThemeCatalog.nativeLight, ThemeCatalog.nativeDark]
                ) { store.choose(ThemeCatalog.nativeAutomaticChoiceID) }
            }

            ForEach(families, id: \.name) { family in
                Section(family.name) {
                    ForEach(family.themes) { theme in
                        row(
                            title: family.themes.count > 1 ? theme.name : theme.family,
                            detail: nil,
                            isSelected: store.choiceID == theme.id,
                            swatches: [theme]
                        ) { store.choose(theme.id) }
                    }
                }
            }

            Section {
            } footer: {
                Text("A theme sets OneRoot's backgrounds, text, selection, accent, and the colors of its own icons: the sidebar's, the icon view's folders, and the toolbar's. File-type icons (a document's, a photo's) come from macOS and keep their own look.")
            }
        }
        .formStyle(.grouped)
    }

    private func row(title: String, detail: String?, isSelected: Bool, swatches: [Theme], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(swatches) { ThemeSwatch(theme: $0) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature window in a theme's colors: sidebar, list, a selected row,
/// text lines, and a folder and accent in the theme's icon colors.
private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        // The native themes leave surfaces to macOS, so stand in typical ones.
        let sidebar = theme.surfaces?.sidebar.color ?? (theme.isDark ? Color(white: 0.17) : Color(white: 0.93))
        let background = theme.surfaces?.background.color ?? (theme.isDark ? Color(white: 0.12) : .white)
        let text = theme.surfaces?.text.color ?? (theme.isDark ? Color(white: 0.9) : Color(white: 0.15))
        let selection = theme.surfaces?.selection.color ?? Color.accentColor.opacity(0.5)
        let accent = theme.surfaces?.accent.color ?? Color.accentColor

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 1).fill(theme.icons.folder.color).frame(width: 10, height: 4)
                RoundedRectangle(cornerRadius: 1).fill(theme.icons.drive.color).frame(width: 10, height: 4)
                RoundedRectangle(cornerRadius: 1).fill(theme.icons.cloud.color).frame(width: 10, height: 4)
            }
            .padding(.horizontal, 4)
            .frame(width: 20, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(sidebar)

            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 1).fill(text).frame(width: 22, height: 3)
                RoundedRectangle(cornerRadius: 1).fill(selection).frame(width: 28, height: 5)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(text.opacity(0.8)).frame(width: 16, height: 2) }
                RoundedRectangle(cornerRadius: 1).fill(text.opacity(0.55)).frame(width: 18, height: 3)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .topTrailing) { Circle().fill(accent).frame(width: 5, height: 5).padding(3) }
        }
        .frame(width: 52, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
