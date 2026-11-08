import SwiftUI

/// A row of filter chips for a `SearchCriteria` — "Kind: Images ✕",
/// "Modified: This Month ✕" — with Add Filter ▾ at the end. Click a chip to
/// change it, ✕ to remove it. The same row in the current folder (under
/// the Context Bar) and in Advanced Search (above the results); what each
/// shows comes from `SearchChipBuilder`.
struct FilterChipBar<Trailing: View>: View {
    @Binding var criteria: SearchCriteria
    let context: SearchChipContext
    /// Why the name pattern can't be used (an unfinished regex).
    var nameError: String?
    var tagSuggestions: [String] = []
    /// Removes a chip's condition; by default, straight from `criteria`.
    var onRemove: ((SearchChip.Field) -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @State private var editing: SearchChip.Field?
    @Environment(\.appTheme) private var theme

    var body: some View {
        let chips = SearchChipBuilder.chips(for: criteria, context: context)
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        chipView(chip)
                    }
                    // A filter being added that has nothing to show yet.
                    if let editing, !chips.contains(where: { $0.field == editing }), let placeholder = placeholder(for: editing) {
                        chipView(placeholder)
                    }
                    AddFilterMenu(context: context) { field in
                        DispatchQueue.main.async { editing = field }
                    }
                    .equatable()
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.vertical, 1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filters")
    }

    private func chipView(_ chip: SearchChip) -> some View {
        let isError = chip.field == .name && nameError != nil
        return HStack(spacing: 2) {
            Button {
                editing = Self.isEditable(chip.field) ? chip.field : nil
            } label: {
                Label(chip.title, systemImage: isError ? "exclamationmark.triangle" : chip.systemImage)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(isError ? (nameError ?? "") : (Self.isEditable(chip.field) ? "Change this filter" : chip.title))
            .accessibilityLabel(chip.title)
            .accessibilityHint(Self.isEditable(chip.field) ? "Changes this filter" : "")
            .popover(isPresented: Binding(
                get: { editing == chip.field },
                set: { if !$0, editing == chip.field { editing = nil } }
            ), arrowEdge: .bottom) {
                FilterChipEditor(criteria: $criteria, field: chip.field, context: context, tagSuggestions: tagSuggestions)
                    .padding(14)
            }
            Button {
                if editing == chip.field { editing = nil }
                if let onRemove { onRemove(chip.field) } else { criteria = SearchChipBuilder.removing(chip.field, from: criteria) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this filter")
            .accessibilityLabel("Remove \(chip.title)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .foregroundStyle(isError ? Color.red : Color.primary)
        .background(Capsule().fill(theme.accentColor.opacity(0.10)))
        .overlay(Capsule().strokeBorder(isError ? Color.red.opacity(0.6) : theme.accentColor.opacity(0.25)))
    }

    /// Hidden files and cloud storage are on/off: remove is all there is.
    private static func isEditable(_ field: SearchChip.Field) -> Bool {
        switch field {
        case .includeHidden, .includeCloudStorage, .tag: return false
        default: return true
        }
    }

    /// The chip shown while a filter chosen from Add Filter is being set
    /// up, before it narrows anything — its editor hangs from it.
    private func placeholder(for field: SearchChip.Field) -> SearchChip? {
        guard let title = AddFilterMenu.placeholderTitle(for: field) else { return nil }
        return SearchChip(field: field, title: title, systemImage: AddFilterMenu.symbol(for: field))
    }
}

extension FilterChipBar where Trailing == EmptyView {
    init(criteria: Binding<SearchCriteria>, context: SearchChipContext, nameError: String? = nil, tagSuggestions: [String] = [], onRemove: ((SearchChip.Field) -> Void)? = nil) {
        self.init(criteria: criteria, context: context, nameError: nameError, tagSuggestions: tagSuggestions, onRemove: onRemove) { EmptyView() }
    }
}

/// Add Filter ▾ — one plain item per kind of filter, each opening that
/// filter's editor (`onCustom`), where presets and multiple choices live.
/// No submenus: on macOS 26 and later a `Menu` nested in a button's
/// `Menu` can't open (its glass window refuses to become key), so only
/// top-level items could be chosen.
///
/// `Equatable` (use `.equatable()`): an open menu that SwiftUI rebuilds
/// closes, so it only redraws when what it shows changes.
struct AddFilterMenu: View, Equatable {
    enum Appearance: Equatable {
        /// "+ Add Filter", in the chip row.
        case addFilter
        /// The filter button by the search field; filled while filtering.
        case icon(filled: Bool)
    }

    let context: SearchChipContext
    var appearance: Appearance = .addFilter
    let onCustom: (SearchChip.Field) -> Void
    /// The search field's menu ends with Advanced Search (#58 — it used to
    /// be a magnifier button beside the field, easy to take for the field's
    /// own search button).
    var onAdvancedSearch: (() -> Void)? = nil

    static func == (lhs: AddFilterMenu, rhs: AddFilterMenu) -> Bool {
        lhs.context == rhs.context && lhs.appearance == rhs.appearance
    }

    /// What the menu offers, in order.
    static func fields(for context: SearchChipContext) -> [SearchChip.Field] {
        var fields: [SearchChip.Field] = [.kinds, .modifiedWithin, .size, .extensions, .tag(""), .itemType]
        if context == .folder { fields.append(.name) }
        return fields
    }

    var body: some View {
        Menu {
            ForEach(Self.fields(for: context), id: \.self) { field in
                if field == .name { Divider() }
                Button {
                    onCustom(field)
                } label: {
                    Label(Self.menuTitle(for: field), systemImage: Self.symbol(for: field))
                }
            }
            if let onAdvancedSearch {
                Divider()
                Button(action: onAdvancedSearch) {
                    Label("Advanced Search\u{2026}", systemImage: "text.magnifyingglass")
                }
                // ⌥⌘/ stays on the main menu's item only: the same key
                // equivalent here too could clash with it.
                .help("Advanced Search (⌥⌘/)")
            }
        } label: {
            switch appearance {
            case .addFilter:
                Label("Add Filter", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            case .icon(let filled):
                Image(systemName: filled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
        .help("Add a filter")
        .accessibilityLabel(appearance == .addFilter ? "Add Filter" : "Filter")
    }

    static func menuTitle(for field: SearchChip.Field) -> String {
        switch field {
        case .kinds: return "Kind\u{2026}"
        case .modifiedWithin, .modifiedDates: return "Date Modified\u{2026}"
        case .size: return "Size\u{2026}"
        case .extensions: return "Extension\u{2026}"
        case .tag: return "Tag\u{2026}"
        case .itemType: return "Files or Folders\u{2026}"
        case .name, .contents: return "Name Options\u{2026}"
        case .includeHidden, .includeCloudStorage: return ""
        }
    }

    static func placeholderTitle(for field: SearchChip.Field) -> String? {
        switch field {
        case .kinds: return "Kind: \u{2026}"
        case .modifiedWithin, .modifiedDates: return "Modified: \u{2026}"
        case .size: return "Size: \u{2026}"
        case .extensions: return "Extension: \u{2026}"
        case .tag: return "Tag: \u{2026}"
        case .itemType: return "Show: \u{2026}"
        case .name: return "Name: \u{2026}"
        case .contents, .includeHidden, .includeCloudStorage: return nil
        }
    }

    static func symbol(for field: SearchChip.Field) -> String {
        switch field {
        case .kinds: return "square.grid.2x2"
        case .modifiedWithin, .modifiedDates: return "calendar"
        case .size: return "scalemass"
        case .extensions: return "doc.badge.ellipsis"
        case .tag: return "tag"
        case .itemType: return "doc.on.doc"
        case .name: return "textformat"
        case .contents: return "text.magnifyingglass"
        case .includeHidden: return "eye"
        case .includeCloudStorage: return "icloud"
        }
    }
}
