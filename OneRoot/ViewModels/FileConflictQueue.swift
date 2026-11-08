import Foundation

/// Questions a view model's copies/moves are waiting on — name conflicts
/// (`FileConflictQueue`), names a destination can't store
/// (`NameFixQueue`). The UI shows `current`; answering it resumes that
/// operation and moves on to the next, so two operations asking at once
/// each get their own answer instead of the second overwriting the first.
@MainActor
final class PromptQueue<Request: Identifiable, Answer> where Request.ID == UUID {
    private var waiting: [(request: Request, continuation: CheckedContinuation<Answer, Never>)] = []

    /// Called whenever `current` changes, so the owner can publish it.
    var onChange: (Request?) -> Void = { _ in }

    var current: Request? { waiting.first?.request }

    func ask(_ request: Request) async -> Answer {
        await withCheckedContinuation { continuation in
            waiting.append((request, continuation))
            if waiting.count == 1 { onChange(request) }
        }
    }

    /// Ignored unless `id` is still the current request's — a dialog
    /// closing after its button already answered mustn't answer the next.
    func answer(_ answer: Answer, to id: UUID) {
        guard let first = waiting.first, first.request.id == id else { return }
        let (_, continuation) = waiting.removeFirst()
        onChange(current)
        continuation.resume(returning: answer)
    }
}

typealias FileConflictQueue = PromptQueue<FileConflictRequest, FileConflictAnswer>
typealias NameFixQueue = PromptQueue<NameFixRequest, NameFixAnswer>
