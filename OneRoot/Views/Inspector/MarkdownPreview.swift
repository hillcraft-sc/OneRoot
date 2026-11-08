import AppKit
import SwiftUI
import WebKit

/// A Markdown file as it reads, for the Inspector's Rendered view:
/// converted with `MarkdownHTMLRenderer` (off the main thread) and shown
/// in a web view with JavaScript off. Images beside the file load; a
/// clicked link opens in its own app instead of inside the Inspector.
struct MarkdownPreview: View {
    let url: URL
    @State private var html: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let html {
                MarkdownWebView(html: html, baseURL: url.deletingLastPathComponent())
            } else if failed {
                Text("This file can't be shown as Markdown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // A new file (or a change to this one) renders afresh; a result
        // that comes in for a file no longer shown is dropped with its task.
        .task(id: url) {
            html = nil
            failed = false
            let url = url
            let result = await Task.detached(priority: .userInitiated) {
                try? TextConversionService().convertedText(of: url, for: .markdownToHTML(styled: true))
            }.value
            guard !Task.isCancelled else { return }
            html = result
            failed = result == nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rendered preview of \(url.lastPathComponent)")
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    /// Exactly the space it's offered, never its own idea of a size (see
    /// `QuickLookPreview.sizeThatFits`).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        // Only a real, finite offer is taken; SwiftUI also asks with no
        // size and with infinity while measuring, and answering those with
        // "infinitely wide" made the Inspector run away.
        func finite(_ value: CGFloat?) -> CGFloat {
            guard let value, value.isFinite else { return 0 }
            return value
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        /// The page itself loads; anything clicked opens outside, the way
        /// a link in Quick Look would.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let target = action.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            NSWorkspace.shared.open(target)
        }
    }
}
