import SwiftUI

/// A lightweight in-app reference, not a full Apple Help Book (no HTML
/// bundle/indexer) — reachable via the Help menu (⌘?), see `OneRootApp`,
/// and the **?** buttons in dialogs and Settings (`HelpButton`). Content is
/// `HelpContent`; searching it is `HelpSearch`.
struct HelpView: View {
    @State private var selectedTopicID: HelpTopicID? = .gettingStarted
    @State private var query = ""
    private var navigator = HelpNavigator.shared

    private var results: [HelpSearch.Result] { HelpSearch.results(for: query, in: HelpContent.topics) }
    private var terms: [String] { HelpSearch.terms(in: query) }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let id = selectedTopicID, let topic = HelpContent.topic(id) {
                HelpTopicView(topic: topic, highlights: terms) { selectedTopicID = $0 }
                    // A fresh scroll position for each topic.
                    .id(id)
            } else {
                Text(query.isEmpty ? "Select a topic" : "No topics match \u{201C}\(query)\u{201D}")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: query) { _, _ in
            // Keep showing the topic you were reading if it still matches.
            let ids = results.map(\.topicID)
            if !query.isEmpty, let selectedTopicID, ids.contains(selectedTopicID) { return }
            selectedTopicID = query.isEmpty ? (selectedTopicID ?? .gettingStarted) : ids.first
        }
        .onAppear(perform: showRequestedTopic)
        .onChange(of: navigator.requestedTopic) { _, _ in showRequestedTopic() }
        .frame(minWidth: 720, minHeight: 500)
        .navigationTitle("OneRoot Help")
    }

    @ViewBuilder
    private var sidebar: some View {
        if query.isEmpty {
            List(selection: $selectedTopicID) {
                ForEach(HelpSection.allCases, id: \.self) { section in
                    Section(section.rawValue) {
                        ForEach(HelpContent.topics.filter { $0.section == section }) { topic in
                            Label(topic.title, systemImage: topic.symbolName)
                                .tag(topic.id)
                        }
                    }
                }
            }
        } else {
            List(selection: $selectedTopicID) {
                ForEach(results, id: \.topicID) { result in
                    if let topic = HelpContent.topic(result.topicID) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(topic.title, systemImage: topic.symbolName)
                            if let snippet = result.snippet {
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .padding(.leading, 24)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(topic.id)
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func showRequestedTopic() {
        guard let topic = navigator.requestedTopic else { return }
        query = ""
        selectedTopicID = topic
        navigator.requestedTopic = nil
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic
    /// Search terms to mark in the text.
    let highlights: [String]
    let onSelect: (HelpTopicID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(topic.title, systemImage: topic.symbolName)
                    .font(.title2.bold())
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    HelpBlockView(block: block, highlights: highlights)
                }
                if !topic.seeAlso.isEmpty {
                    seeAlso
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var seeAlso: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("See Also")
                .font(.headline)
            ForEach(topic.seeAlso, id: \.self) { id in
                if let related = HelpContent.topic(id) {
                    Button {
                        onSelect(id)
                    } label: {
                        Label(related.title, systemImage: related.symbolName)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock
    let highlights: [String]

    var body: some View {
        switch block {
        case .heading(let text):
            Text(styled(text))
                .font(.headline)
                .padding(.top, 6)
        case .paragraph(let text):
            Text(styled(text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                        Text(styled(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textSelection(.enabled)
                }
            }
        case .shortcuts(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(styled(row.0))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(styled(row.1))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textSelection(.enabled)
                }
            }
        case .terms(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                    GridRow {
                        Text(styled(row.0))
                            .foregroundStyle(.secondary)
                            .frame(width: 190, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(styled(row.1))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }

    /// The text's inline Markdown, with every search term marked.
    private func styled(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        for term in highlights {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[range].backgroundColor = Color.yellow.opacity(0.45)
                searchStart = range.upperBound
            }
        }
        return text
    }
}

#Preview {
    HelpView()
}
