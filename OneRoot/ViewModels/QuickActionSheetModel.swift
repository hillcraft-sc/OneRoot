import Foundation
import Observation

/// Backs a Quick Action sheet: reads what the preview needs (image sizes
/// and metadata, PDF page counts, line counts and a converted sample) off
/// the main thread, keeps the Combine order, and plans the request as the
/// options change.
@MainActor
@Observable
final class QuickActionSheetModel {
    let action: QuickAction
    /// In Combine into PDF, the page order — rearranged in the sheet.
    private(set) var urls: [URL]
    private(set) var isLoading = true
    private(set) var imageInfo: [URL: ImageInfo] = [:]
    private(set) var pageCounts: [URL: Int] = [:]
    private(set) var textInfo: [URL: TextInfo] = [:]
    /// Word, RTF, OpenDocument, and plain-text files among `urls` — printed
    /// to PDF (Convert to PDF, and Combine into PDF).
    let documents: Set<URL>
    /// Text conversions: the first file's result, as it'll be written.
    private(set) var preview: String?

    private let planner: QuickActionPlanner

    init(action: QuickAction, urls: [URL], planner: QuickActionPlanner = QuickActionPlanner()) {
        self.action = action
        self.urls = urls
        self.planner = planner
        let catalog = QuickActionCatalog()
        documents = Set(urls.filter { url in
            let kind = catalog.kind(of: FileNode(url: url, name: url.lastPathComponent, isDirectory: false, size: nil, modificationDate: nil, kind: nil))
            return kind == .document || kind == .plainText
        })
    }

    /// Whether any selected image is in a lossy format (Resize then asks
    /// for a quality).
    var hasLossyImages: Bool {
        imageInfo.values.contains { $0.format?.isLossy ?? false }
    }

    func load() async {
        let urls = urls
        let action = action
        let services = QuickActionServices.current
        let work = Task.detached(priority: .userInitiated) { () -> ([URL: ImageInfo], [URL: Int], [URL: TextInfo]) in
            var info: [URL: ImageInfo] = [:]
            var pages: [URL: Int] = [:]
            var text: [URL: TextInfo] = [:]
            let images = services.images
            let pdfs = services.pdfs
            let texts = TextConversionService()
            for url in urls {
                if Task.isCancelled { break }
                if action == .combineIntoPDF {
                    pages[url] = pdfs.pageCount(of: url)
                } else if action.isTextConversion {
                    text[url] = try? texts.info(for: url)
                } else {
                    info[url] = try? images.info(for: url)
                }
            }
            return (info, pages, text)
        }
        // Closing the sheet cancels `.task`, and with it the reading.
        let (info, pages, text) = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled else { return }
        imageInfo = info
        pageCounts = pages
        textInfo = text
        isLoading = false
    }

    /// Converts the first readable file for the preview — again whenever
    /// the options change (the sheet's `.task(id:)` cancels the last one).
    func loadPreview(_ request: QuickActionRequest) async {
        guard action.isTextConversion, let url = urls.first(where: { textInfo[$0] != nil }) else {
            preview = nil
            return
        }
        let work = Task.detached(priority: .userInitiated) {
            try? TextConversionService().convertedText(of: url, for: request)
        }
        let text = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled else { return }
        // For a page, the body: the head is the same boilerplate every time.
        let shown = text.map { text -> String in
            guard action == .markdownToHTML, let body = text.range(of: "<body>\n") else { return text }
            return String(text[body.upperBound...])
        }
        // The start is enough to judge it by.
        preview = shown.map { String($0.prefix(4000)) }
    }

    func plan(_ request: QuickActionRequest) -> QuickActionPlan {
        planner.plan(request, sources: urls, imageInfo: imageInfo, pageCounts: pageCounts, textInfo: textInfo, documents: documents)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // SwiftUI's `move(fromOffsets:toOffset:)`, spelled out so this builds
        // without SwiftUI.
        let moving = source.map { urls[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.reversed() { urls.remove(at: index) }
        urls.insert(contentsOf: moving, at: destination - before)
    }

    /// Moves the item at `index` one place up (`by: -1`) or down (`1`).
    func move(at index: Int, by offset: Int) {
        let target = index + offset
        guard urls.indices.contains(index), urls.indices.contains(target) else { return }
        urls.swapAt(index, target)
    }
}
