import Foundation

enum ResolvedAddress: Equatable {
    case local(URL)
    case networkShare(URL)
}

enum PathResolutionError: LocalizedError, Equatable {
    case empty
    case unsupportedFormat(String)
    case notFound(String)
    case notADirectory(String)
    case invalidNetworkAddress(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return nil
        case .unsupportedFormat:
            return "Enter an absolute path starting with / or ~, or a smb:// address."
        case .notFound(let path):
            return "\"\(path)\" doesn't exist."
        case .notADirectory(let path):
            return "\"\(path)\" isn't a folder."
        case .invalidNetworkAddress:
            return "That doesn't look like a valid network address, e.g. smb://server/share."
        }
    }
}

/// Parses and validates address-bar input. UI-agnostic — no SwiftUI/AppKit
/// imports (see CLAUDE.md §1). Network addresses are recognized here but
/// actually mounted by `NetworkShareService`, which the caller invokes for
/// the `.networkShare` case.
struct PathResolver {
    private static let networkSchemes = ["smb", "afp", "nfs"]

    func resolve(_ input: String) -> Result<ResolvedAddress, PathResolutionError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let looksLikeNetworkAddress = Self.networkSchemes.contains { trimmed.lowercased().hasPrefix($0 + "://") }
        if looksLikeNetworkAddress {
            guard let url = URL(string: trimmed), url.host != nil else {
                return .failure(.invalidNetworkAddress(trimmed))
            }
            return .success(.networkShare(url))
        }

        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else {
            return .failure(.unsupportedFormat(trimmed))
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
        guard exists else { return .failure(.notFound(expanded)) }
        guard isDirectory.boolValue else { return .failure(.notADirectory(expanded)) }

        return .success(.local(URL(fileURLWithPath: expanded, isDirectory: true)))
    }

    /// Splits address-bar input into "the folder to look in" and "the
    /// prefix to match its children's names against," for live
    /// autocomplete as the user types. `nil` for input that isn't a local
    /// path at all (network addresses, or anything not starting with
    /// `/`/`~`) — suggesting folder names doesn't make sense before a
    /// share is actually mounted.
    func splitForAutocomplete(_ input: String) -> (directory: URL, prefix: String)? {
        guard input.hasPrefix("/") || input.hasPrefix("~") else { return nil }
        if input == "~" {
            return (FileManager.default.homeDirectoryForCurrentUser, "")
        }
        // Checked on the raw input, before expansion: `expandingTildeInPath`
        // isn't guaranteed to preserve a trailing slash, so relying on it
        // surviving into `expanded` is fragile.
        let hasTrailingSlash = input.hasSuffix("/")
        let expanded = (input as NSString).expandingTildeInPath
        if hasTrailingSlash {
            return (URL(fileURLWithPath: expanded, isDirectory: true), "")
        }
        guard let lastSlash = expanded.lastIndex(of: "/") else { return nil }
        let directoryPath = String(expanded[..<lastSlash])
        let prefix = String(expanded[expanded.index(after: lastSlash)...])
        return (URL(fileURLWithPath: directoryPath.isEmpty ? "/" : directoryPath, isDirectory: true), prefix)
    }
}
