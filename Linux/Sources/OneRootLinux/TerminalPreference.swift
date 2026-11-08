import Foundation

/// Which terminal Open in Terminal starts: the command set in Settings, else
/// $TERMINAL, else the first of the well-known terminals that is installed.
/// A command may carry arguments ("kitty --single-instance"); the terminal is
/// started with the folder as its working directory.
struct TerminalPreference {
    static let key = "com.oneroot.linux.terminalCommand"
    static let knownTerminals = ["xdg-terminal-exec", "kgx", "gnome-terminal", "ptyxis", "konsole", "ghostty", "alacritty",
                                 "kitty", "foot", "wezterm", "xfce4-terminal", "tilix", "xterm"]

    enum Resolution: Equatable {
        case found(executable: String, arguments: [String])
        /// The command in Settings isn't installed.
        case missingConfigured(String)
        case noneFound
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The command chosen in Settings; `nil` means the automatic choice.
    var command: String? {
        get {
            let text = defaults.string(forKey: Self.key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        nonmutating set {
            let text = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty { defaults.set(text, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        }
    }

    func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Resolution {
        let paths = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        func find(_ name: String) -> String? {
            if name.hasPrefix("/") { return isExecutable(name) ? name : nil }
            return paths.map { "\($0)/\(name)" }.first(where: isExecutable)
        }
        func split(_ command: String) -> (name: String, arguments: [String]) {
            let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
            return (words.first ?? command, Array(words.dropFirst()))
        }
        if let configured = command {
            let parts = split(configured)
            guard let executable = find(parts.name) else { return .missingConfigured(configured) }
            return .found(executable: executable, arguments: parts.arguments)
        }
        var candidates: [String] = []
        if let terminal = environment["TERMINAL"], !terminal.isEmpty { candidates.append(terminal) }
        candidates += Self.knownTerminals
        for candidate in candidates {
            let parts = split(candidate)
            if let executable = find(parts.name) { return .found(executable: executable, arguments: parts.arguments) }
        }
        return .noneFound
    }
}
