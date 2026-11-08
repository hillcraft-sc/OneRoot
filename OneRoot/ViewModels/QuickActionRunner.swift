import Foundation

/// Carries out a Quick Action's plan: each transform off the main thread,
/// with a File Operations entry (item by item, Cancel between items), and
/// one Undo step that takes away the files it made. Outputs written before
/// a failure or Cancel stay, and are undoable too.
@MainActor
struct QuickActionRunner {
    var services: QuickActionServices = .current
    var textService = TextConversionService()
    var progressCenter: FileOperationProgressCenter = .shared
    var undoCenter: FileUndoCenter = .shared

    struct Result {
        let created: [URL]
        /// `nil` when it finished or was cancelled.
        let error: Error?
    }

    func run(_ request: QuickActionRequest, plan: QuickActionPlan) async -> Result {
        let work = plan.items.filter { !$0.isSkipped }
        guard !work.isEmpty else { return Result(created: [], error: nil) }
        let action = request.action
        let current = CurrentTask()
        let progressID = progressCenter.begin(
            title: Self.title(request, work: work),
            symbolName: action.systemImage,
            totalBytes: 0,
            isIndeterminate: true,
            sourceFolder: FileOperationProgressCenter.commonFolder(work.map(\.source)),
            destinationFolder: plan.combinedOutput?.deletingLastPathComponent(),
            itemCount: work.count,
            cancel: { current.cancel() }
        )

        var created: [URL] = []
        var finished = 0
        var failure: Error?
        do {
            switch request {
            case .combine:
                guard let output = plan.combinedOutput else { break }
                let names = work.map(\.source.lastPathComponent)
                // Documents become PDFs first (on the main thread, as
                // printing must), in scratch files gone afterwards.
                var scratch: [URL] = []
                defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }
                var sources: [URL] = []
                for (index, item) in work.enumerated() {
                    guard plan.documents.contains(item.source) else {
                        sources.append(item.source)
                        continue
                    }
                    if current.isCancelled { throw CancellationError() }
                    progressCenter.setCurrentItem(progressID, index: index, name: names[index])
                    let data = try await services.documents.pdfData(for: item.source)
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
                    try data.write(to: file)
                    scratch.append(file)
                    sources.append(file)
                }
                let center = progressCenter
                let service = services.pdfs
                // A constant for the detached work (Swift 6 won't capture
                // a `var` there).
                let finalSources = sources
                let written = try await current.run {
                    try service.combine(finalSources, output: output, progress: { index in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { center.setCurrentItem(progressID, index: index, name: names[index]) }
                        }
                    })
                }
                created.append(written)
                finished = work.count
            case .convertToPDF:
                for (index, item) in work.enumerated() {
                    guard let output = item.output else { continue }
                    if current.isCancelled { throw CancellationError() }
                    progressCenter.setCurrentItem(progressID, index: index, name: item.source.lastPathComponent)
                    created.append(try await services.documents.convert(item.source, output: output))
                    finished = index + 1
                }
            default:
                for (index, item) in work.enumerated() {
                    guard let output = item.output else { continue }
                    try Task.checkCancellation()
                    if current.isCancelled { throw CancellationError() }
                    progressCenter.setCurrentItem(progressID, index: index, name: item.source.lastPathComponent)
                    let service = services.images
                    let textService = textService
                    let source = item.source
                    let written = try await current.run {
                        switch request {
                        case .textToMarkdown, .markdownToHTML, .htmlToMarkdown:
                            return try textService.convert(source, for: request, output: output)
                        case .resize(let target, let quality):
                            return try service.resize(source, to: target, quality: quality, output: output)
                        case .convert(let format, let quality):
                            return try service.convert(source, to: format, quality: quality, output: output)
                        case .removeMetadata, .combine, .convertToPDF:
                            return try service.removeMetadata(source, output: output)
                        }
                    }
                    created.append(written)
                    finished = index + 1
                }
            }
            progressCenter.finish(progressID)
        } catch is CancellationError {
            progressCenter.finish(progressID, outcome: .cancelled, finishedItems: finished)
        } catch {
            failure = error
            progressCenter.finish(progressID, outcome: .failure(error, finished: finished, of: work.count), finishedItems: finished)
        }
        undoCenter.record(created.map { .created($0) }, actionName: Self.undoName(action, count: work.count))
        return Result(created: created, error: failure)
    }

    /// "Resizing “a.jpg”", "Converting 3 images to PNG", "Combining 4 items into “Combined.pdf”".
    static func title(_ request: QuickActionRequest, work: [QuickActionPlanItem]) -> String {
        let urls = work.map(\.source)
        switch request {
        case .resize:
            return FileOperationProgressCenter.title("Resizing", urls)
        case .convert(let format, _):
            return FileOperationProgressCenter.title("Converting", urls, suffix: " to \(format.title)")
        case .removeMetadata:
            return FileOperationProgressCenter.title("Removing metadata from", urls)
        case .combine(let name):
            return FileOperationProgressCenter.title("Combining", urls, suffix: " into \u{201C}\(name).pdf\u{201D}")
        case .textToMarkdown, .htmlToMarkdown:
            return FileOperationProgressCenter.title("Converting", urls, suffix: " to Markdown")
        case .convertToPDF:
            return FileOperationProgressCenter.title("Converting", urls, suffix: " to PDF")
        case .markdownToHTML:
            return FileOperationProgressCenter.title("Converting", urls, suffix: " to HTML")
        }
    }

    /// "Undo Resize Image", "Undo Convert 3 Images", "Undo Combine into PDF".
    static func undoName(_ action: QuickAction, count: Int) -> String {
        switch action {
        case .combineIntoPDF:
            return "Combine into PDF"
        case .textToMarkdown, .htmlToMarkdown:
            return count == 1 ? "Convert to Markdown" : "Convert \(count) Files to Markdown"
        case .markdownToHTML:
            return count == 1 ? "Convert to HTML" : "Convert \(count) Files to HTML"
        case .convertToPDF:
            return count == 1 ? "Convert to PDF" : "Convert \(count) Files to PDF"
        case .resizeImages, .convertImages, .removeImageMetadata:
            let noun = count == 1 ? "Image" : "\(count) Images"
            return "\(action.verb) \(noun)"
        }
    }
}

/// The detached task doing the current item, so Cancel (which comes from
/// the File Operations card, not from this task) can stop it — the
/// services check for cancellation between frames and pages.
@MainActor
private final class CurrentTask {
    private var task: Task<URL, Error>?
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
        task?.cancel()
    }

    func run(_ body: @escaping @Sendable () throws -> URL) async throws -> URL {
        if isCancelled { throw CancellationError() }
        let task = Task.detached(priority: .userInitiated, operation: body)
        self.task = task
        defer { self.task = nil }
        return try await task.value
    }
}
