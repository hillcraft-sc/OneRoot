import AppKit
import SwiftUI

/// The Software Update window: OneRoot ▸ Check for Updates…, or opened by
/// an automatic check that found a newer version. Nothing is downloaded or
/// installed from here — Download opens the disk image in your browser.
struct UpdateView: View {
    var center: UpdateCenter = .shared
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    headline
                }
            }
            content
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var headline: some View {
        switch center.state {
        case .idle, .checking:
            Text("Checking for updates\u{2026}").font(.headline)
            ProgressView().controlSize(.small)
        case .upToDate:
            Text("OneRoot is up to date").font(.headline)
            Text("You have the latest version, \(center.currentVersion).")
                .foregroundStyle(.secondary)
        case .available(let release):
            Text("OneRoot \(release.version) is available").font(.headline)
            Text("You have \(center.currentVersion).\(release.publishedAt.map { " Released \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "")")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Couldn\u{2019}t check for updates").font(.headline)
            Text(message).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch center.state {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            buttons { Button("OK") { dismissWindow() }.keyboardShortcut(.defaultAction) }
        case .failed:
            buttons {
                Button("Close") { dismissWindow() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { center.checkNow() }.keyboardShortcut(.defaultAction)
            }
        case .available(let release):
            if !release.notes.isEmpty {
                ScrollView {
                    Text(Self.markdown(release.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            }
            buttons {
                Button("Skip This Version") {
                    center.skip(release)
                    dismissWindow()
                }
                .help("Don\u{2019}t remind me about \(release.version) again")
                Spacer()
                Button("Later") { dismissWindow() }
                    .keyboardShortcut(.cancelAction)
                Button("Download") {
                    NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
                    dismissWindow()
                }
                .keyboardShortcut(.defaultAction)
                .help("Download the disk image; open it and drag OneRoot to Applications to replace this version")
            }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Link("Release notes on GitHub", destination: URL(string: "https://github.com/hillcraft-sc/OneRoot/releases") ?? URL(fileURLWithPath: "/"))
                .font(.caption)
            Spacer()
            content()
        }
    }

    /// Release notes are Markdown; headings and lists keep their line breaks.
    static func markdown(_ text: String) -> AttributedString {
        // List markers read better as bullets in plain text.
        let bulleted = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop { $0 == " " }
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return String(line) }
            return String(line.prefix(line.count - trimmed.count)) + "\u{2022} " + trimmed.dropFirst(2)
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: bulleted, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(bulleted)
    }
}
