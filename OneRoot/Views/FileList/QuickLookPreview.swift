import AppKit
import QuickLookUI
import SwiftUI

/// Hosts a `QLPreviewView` — the same renderer as the spacebar Quick Look
/// panel, embedded. `.normal` style gives video/audio their play controls.
///
/// The preview sits inside a plain container that SwiftUI sizes. Quick
/// Look's own views (a remote view per file type) bring sizes and
/// constraints of their own that change as a preview loads; hosted
/// directly, those reached SwiftUI's layout and pushed the Inspector wider
/// than its pane — its contents zoomed and clipped, then back again. The
/// container answers only with the space it's offered and resizes the
/// preview to fill it.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> Container {
        Container(url: url)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Container, context: Context) -> CGSize? {
        // Only a real, finite offer is taken; SwiftUI also measures with
        // no size and with infinity.
        func finite(_ value: CGFloat?) -> CGFloat {
            guard let value, value.isFinite else { return 0 }
            return value
        }
        return CGSize(width: finite(proposal.width), height: finite(proposal.height))
    }

    func updateNSView(_ container: Container, context: Context) {
        container.show(url)
    }

    static func dismantleNSView(_ container: Container, coordinator: ()) {
        container.close()
    }

    /// No intrinsic size and no constraints: whatever the preview inside
    /// wants stays inside.
    final class Container: NSView {
        private let preview: QLPreviewView

        init(url: URL) {
            // `shouldCloseWithWindow = false`: SwiftUI may tear this view
            // down and rebuild it while the window stays open;
            // `dismantleNSView` closes it explicitly instead.
            preview = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
            super.init(frame: .zero)
            preview.shouldCloseWithWindow = false
            preview.translatesAutoresizingMaskIntoConstraints = true
            preview.autoresizingMask = [.width, .height]
            preview.frame = bounds
            addSubview(preview)
            preview.previewItem = url as NSURL
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func layout() {
            super.layout()
            if preview.frame != bounds { preview.frame = bounds }
        }

        func show(_ url: URL) {
            guard (preview.previewItem as? NSURL) as URL? != url else { return }
            preview.previewItem = url as NSURL
        }

        func close() {
            preview.close()
        }
    }
}
