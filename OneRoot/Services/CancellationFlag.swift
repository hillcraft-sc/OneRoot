import Foundation

/// Something in flight that can really stop and carry on later — given
/// to `FileOperationProgressCenter`, whose Pause button calls it.
protocol PauseControl: AnyObject, Sendable {
    func pause()
    func resume()
}

/// Lets a long copy be stopped or paused from another thread — set by the
/// progress popup's Cancel and Pause, checked by `FileCopier` between (and
/// within) files. A paused copy waits right there, file still open, and
/// carries on from the same byte when resumed; cancelling wakes it to stop.
final class CancellationFlag: PauseControl, @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var paused = false

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return paused
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    func pause() {
        condition.lock()
        paused = true
        condition.unlock()
    }

    func resume() {
        condition.lock()
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks the calling (copying) thread while paused; returns once
    /// resumed or cancelled. Never call it from the main thread.
    func waitWhilePaused() {
        condition.lock()
        while paused && !cancelled {
            condition.wait()
        }
        condition.unlock()
    }
}
