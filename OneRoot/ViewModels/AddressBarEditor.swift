import Foundation

/// The path bar's two presentations — clickable breadcrumbs, or a typed
/// path — and every way of moving between them, kept out of the view so it
/// can be tested. One instance per path bar; the view feeds it events and
/// acts on what it returns.
///
/// In "Text field" style (Settings ▸ General ▸ Address bar) the bar is
/// always the text field: it never "ends" editing, it just keeps the
/// current path.
struct AddressBarEditor: Equatable {
    enum Mode: Equatable {
        case breadcrumbs
        case editing
    }

    /// What submitting the typed text should do.
    enum Submission: Equatable {
        case navigate(URL)
        case connect(URL)
        /// Invalid (or empty) — stay editing, with `errorMessage` set.
        case stay
    }

    let alwaysTextField: Bool
    private(set) var mode: Mode
    var text: String
    private(set) var errorMessage: String?

    init(alwaysTextField: Bool, currentPath: String) {
        self.alwaysTextField = alwaysTextField
        mode = alwaysTextField ? .editing : .breadcrumbs
        text = currentPath
    }

    var isEditing: Bool { mode == .editing }

    /// ⇧⌘G, the pencil, or a click on the bar's empty space: type a path,
    /// starting from the current one (the view selects it all).
    mutating func begin(currentPath: String) {
        mode = .editing
        text = currentPath
        errorMessage = nil
    }

    /// Esc (with no suggestions open), or clicking away: back to
    /// breadcrumbs, dropping whatever was half-typed. Never navigates.
    mutating func cancel(currentPath: String) {
        text = currentPath
        errorMessage = nil
        if !alwaysTextField { mode = .breadcrumbs }
    }

    /// Return or Go. Only a valid path leaves edit mode — and only once
    /// the navigation (or the share's mount) has happened (`finish`).
    mutating func submit(_ resolution: Result<ResolvedAddress, PathResolutionError>) -> Submission {
        switch resolution {
        case .success(.local(let url)):
            errorMessage = nil
            return .navigate(url)
        case .success(.networkShare(let url)):
            errorMessage = nil
            return .connect(url)
        case .failure(let error):
            errorMessage = error.errorDescription
            return .stay
        }
    }

    /// A share couldn't be mounted: stay editing, say why.
    mutating func connectionFailed(_ message: String) {
        errorMessage = message
    }

    /// The navigation a submission asked for has happened.
    mutating func finish(currentPath: String) {
        cancel(currentPath: currentPath)
    }

    /// The pane's folder changed some other way (Back, a click in the
    /// list). The breadcrumbs follow by themselves; typed text is only
    /// replaced when nobody's typing in it.
    mutating func currentPathChanged(to path: String, isTyping: Bool) {
        guard !isTyping else { return }
        text = path
        errorMessage = nil
    }

    /// The bar now belongs to a different pane (another tab, or the other
    /// side of Dual Pane): anything typed was for the old one.
    mutating func paneChanged(currentPath: String) {
        cancel(currentPath: currentPath)
    }

    /// Typing clears a stale error.
    mutating func textEdited() {
        errorMessage = nil
    }
}
