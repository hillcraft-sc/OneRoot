import Foundation

/// How "Open in Terminal" should start a custom terminal app, decided before
/// anything is launched so the choice can be tested without opening one.
/// Foundation-only; `OpenInTerminal.swift` carries the plan out with
/// `NSWorkspace`.
enum TerminalLaunchPlan: Equatable {
    /// No open-folder argument configured: macOS's normal "open this folder
    /// with that app", which Terminal.app and iTerm2 support.
    case documentOpen
    /// The app is already running: run it again with the folder argument.
    /// Single-instance (Electron) terminals like Tabby hand that to the copy
    /// that's already open, which opens a window or tab there.
    case sendArguments
    /// The app isn't running: start it plainly first, wait until it has
    /// finished starting, then send the argument as above. Handing the
    /// folder to a copy that's still starting up is what left Tabby open
    /// with no window (#15).
    case launchThenSendArguments

    static func plan(hasWorkingDirectoryFlag: Bool, isRunning: Bool) -> TerminalLaunchPlan {
        guard hasWorkingDirectoryFlag else { return .documentOpen }
        return isRunning ? .sendArguments : .launchThenSendArguments
    }
}
