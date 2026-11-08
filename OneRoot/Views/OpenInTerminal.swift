import AppKit

/// Opens `url` in the user's configured terminal app (see
/// `TerminalPreferenceService`), or Terminal.app if none is configured.
///
/// The default (Terminal.app) path goes through AppleScript — there's no
/// document-open API for "start a shell here," Terminal doesn't treat a
/// folder as an openable document — the same mechanism Finder's own "New
/// Terminal at Folder" service uses under the hood. Triggers a one-time
/// Automation permission prompt (`NSAppleEventsUsageDescription`).
///
/// A custom terminal app goes one of two ways, both configured in
/// Settings (see `TerminalPreferenceService`):
///
/// - No open-folder argument set: `NSWorkspace.open(_:
///   withApplicationAt:)` — the same "open with" mechanism Finder itself
///   uses. Works for apps (Terminal.app, iTerm2, and others) that
///   implement macOS's document-open convention for folders as "start a
///   session there."
/// - An argument is set: `NSWorkspace.openApplication(at:configuration:)`
///   with `[argument, url.path]` as launch arguments instead — for apps
///   (Tabby, kitty, Alacritty, and other non-native/Electron terminals
///   among them) that don't implement that convention and need an
///   explicit CLI invocation instead, the same way their own documented
///   shell integrations invoke them. Not always a `--flag`: Tabby's own
///   CLI, for example, is a yargs-style subcommand (`tabby open <dir>`),
///   so the "argument" there is just the plain word `open`.
func openInTerminal(_ url: URL) {
    let preferences = TerminalPreferenceService()
    if let bundleIdentifier = preferences.bundleIdentifier(),
       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
        let flag = preferences.workingDirectoryFlag()
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        switch TerminalLaunchPlan.plan(hasWorkingDirectoryFlag: flag != nil, isRunning: isRunning) {
        case .documentOpen:
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        case .sendArguments:
            sendFolderArgument(flag ?? "", for: url, to: appURL)
        case .launchThenSendArguments:
            Task { @MainActor in
                await launchAndWait(for: appURL)
                sendFolderArgument(flag ?? "", for: url, to: appURL)
            }
        }
        return
    }

    let escapedPath = url.path
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let script = """
    tell application "Terminal"
        do script "cd " & quoted form of "\(escapedPath)"
        activate
    end tell
    """
    NSAppleScript(source: script)?.executeAndReturnError(nil)
}

/// Runs the terminal app again with `[flag, folder]` as its arguments. A
/// fresh instance each time, because LaunchServices only passes arguments
/// to an instance it starts; an already-running single-instance app forwards
/// them to the copy that's open and the new one exits.
private func sendFolderArgument(_ flag: String, for url: URL, to appURL: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [flag, url.path]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
}

/// Starts the terminal app plainly and waits until it can take a folder: its
/// launch has finished, plus a short settle for Electron-style apps, which
/// report "finished launching" before their single-instance handling and
/// first window are ready.
@MainActor
private func launchAndWait(for appURL: URL) async {
    guard let app = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) else {
        return
    }
    for _ in 0..<100 where !app.isFinishedLaunching {
        try? await Task.sleep(for: .milliseconds(100))
    }
    try? await Task.sleep(for: .milliseconds(1_500))
}
