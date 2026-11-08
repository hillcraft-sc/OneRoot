import Foundation

/// What to do after a Move to Trash with items whose volume has no Trash
/// (NFS/SMB shares and the like): ask once whether to delete those
/// immediately, then do it and record it in File Operations. Shared by
/// `FileListViewModel` and `FolderHierarchyViewModel`.
@MainActor
enum TrashFallback {
    struct Outcome {
        /// The trash result minus the items deleted for good. Items the
        /// user chose not to delete stay failures (Retry asks again).
        var result: TrashResult
        /// The items deleted for good.
        var deleted: Set<URL> = []
        /// The error worth showing: the delete's if it failed, otherwise
        /// the first trash failure other than "no Trash" (the user has
        /// just answered about those).
        var errorMessage: String?
    }

    static func deleteItemsWithoutTrash(
        _ result: TrashResult,
        confirm: ([URL]) -> Bool,
        fileSystemService: FileSystemService
    ) async -> Outcome {
        let urls = result.withoutTrash
        let otherFailure = result.failures.first { !urls.contains($0.url) }
        var outcome = Outcome(result: result, errorMessage: otherFailure?.error.localizedDescription)
        guard !urls.isEmpty, confirm(urls) else { return outcome }
        var deleteOutcome = FileOperationOutcome.succeeded
        do {
            try await fileSystemService.deletePermanently(urls)
        } catch {
            deleteOutcome = .failure(error, finished: TrashFallback.goneCount(urls), of: urls.count)
            outcome.errorMessage = error.localizedDescription
        }
        Platform.progress.record(
            title: FileOperationLabels.title("Deleting", urls, suffix: " immediately"),
            symbolName: "xmark.bin",
            outcome: deleteOutcome,
            itemCount: urls.count,
            finishedItems: deleteOutcome.isFailure ? TrashFallback.goneCount(urls) : urls.count,
            sourceFolder: FileOperationLabels.commonFolder(urls)
        )
        // Whatever couldn't be deleted either still shows as a trash failure.
        let deleted = deleteOutcome.isFailure ? urls.filter { (try? $0.checkResourceIsReachable()) != true } : urls
        outcome.deleted = Set(deleted)
        outcome.result = result.removingFailures(deleted)
        return outcome
    }

    /// How many of `urls` are gone — the progress a partly failed delete made.
    nonisolated static func goneCount(_ urls: [URL]) -> Int {
        urls.filter { (try? $0.checkResourceIsReachable()) != true }.count
    }
}
