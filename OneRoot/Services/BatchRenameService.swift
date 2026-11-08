import Foundation

/// One way of renaming a batch of items — Finder's Rename dialog plus regex
/// and case changes. Applied to each name *without* its extension unless
/// `includeExtension` is on, so "IMG_001.jpg" → "Vacation 1.jpg" keeps the
/// ".jpg".
enum BatchRenameRule: Equatable {
    enum Position: String, CaseIterable {
        case before, after
    }

    enum CaseStyle: String, CaseIterable {
        case lowercase, uppercase, titleCase
    }

    case replace(find: String, with: String, caseSensitive: Bool, regex: Bool)
    case add(text: String, position: Position)
    /// "base 1", "base 2", … (or "1 base" with `.before`), counting from
    /// `start`, zero-padded to `digits`.
    case format(base: String, counterPosition: Position, start: Int, digits: Int)
    case changeCase(CaseStyle)
}

/// Why a proposed name can't be used.
enum BatchRenameProblem: Equatable {
    case empty
    case invalidCharacter
    case startsWithDot
    case duplicateInBatch
    case existsInFolder

    var message: String {
        switch self {
        case .empty: return "Name is empty"
        case .invalidCharacter: return "Names can't contain “/” or “:”"
        case .startsWithDot: return "A name starting with “.” would hide it"
        case .duplicateInBatch: return "Two items would get this name"
        case .existsInFolder: return "Something with this name is already here"
        }
    }
}

enum BatchRenameError: LocalizedError {
    case invalidRegex(String)
    case failed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidRegex(let pattern):
            return "“\(pattern)” isn't a valid regular expression."
        case .failed(let name, let underlying):
            return "Couldn't rename “\(name)”, so nothing was renamed: \(underlying.localizedDescription)"
        }
    }
}

/// UI-agnostic batch renaming: computing new names from a rule, checking
/// them, and applying them all-or-nothing.
struct BatchRenameService {
    /// The new name for each of `urls`, in order. Throws only for an
    /// invalid regex.
    func newNames(for urls: [URL], rule: BatchRenameRule, includeExtension: Bool = false) throws -> [String] {
        let regex: NSRegularExpression?
        if case .replace(let find, _, let caseSensitive, true) = rule, !find.isEmpty {
            do {
                regex = try NSRegularExpression(pattern: find, options: caseSensitive ? [] : [.caseInsensitive])
            } catch {
                throw BatchRenameError.invalidRegex(find)
            }
        } else {
            regex = nil
        }

        return urls.enumerated().map { index, url in
            let name = url.lastPathComponent
            let (stem, ext) = Self.split(name, includeExtension: includeExtension)
            let newStem = Self.apply(rule, to: stem, index: index, regex: regex)
            return ext.isEmpty ? newStem : "\(newStem).\(ext)"
        }
    }

    /// Problems by index into `urls`/`newNames`; an index with no entry is
    /// fine. Name comparisons are case-insensitive, like the default APFS
    /// volume, so "Photo.jpg" and "photo.jpg" count as a clash.
    func problems(for urls: [URL], newNames: [String]) -> [Int: BatchRenameProblem] {
        var problems: [Int: BatchRenameProblem] = [:]
        var countsByFolder: [String: Int] = [:]
        for (url, name) in zip(urls, newNames) {
            countsByFolder[Self.key(url.deletingLastPathComponent(), name), default: 0] += 1
        }
        let renamedAway = Set(urls.map { Self.key($0.deletingLastPathComponent(), $0.lastPathComponent) })

        for (index, (url, name)) in zip(urls, newNames).enumerated() {
            let folder = url.deletingLastPathComponent()
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                problems[index] = .empty
            } else if name.contains("/") || name.contains(":") {
                problems[index] = .invalidCharacter
            } else if name.hasPrefix(".") && !url.lastPathComponent.hasPrefix(".") {
                problems[index] = .startsWithDot
            } else if countsByFolder[Self.key(folder, name), default: 0] > 1 {
                problems[index] = .duplicateInBatch
            } else if !renamedAway.contains(Self.key(folder, name)),
                      (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)) != nil {
                // Taken by something that isn't itself being renamed away.
                problems[index] = .existsInFolder
            }
        }
        return problems
    }

    /// Renames every item that changes, all or nothing: each first moves to
    /// a temporary name, then to its new one, so swaps ("a"↔"b") and
    /// case-only changes work. On any failure everything is put back and
    /// this throws. Returns the changes made, for Undo.
    func apply(urls: [URL], newNames: [String]) async throws -> [FileChange] {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let changing = zip(urls, newNames).filter { $0.lastPathComponent != $1 }
            var staged: [(original: URL, temporary: URL, final: URL)] = []
            var finished: [(original: URL, temporary: URL, final: URL)] = []

            func rollBack() {
                for item in finished.reversed() {
                    try? fileManager.moveItem(at: item.final, to: item.temporary)
                }
                for item in staged.reversed() {
                    try? fileManager.moveItem(at: item.temporary, to: item.original)
                }
            }

            for (url, name) in changing {
                let temporary = url.deletingLastPathComponent()
                    .appendingPathComponent(".oneroot-rename-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    try fileManager.moveItem(at: url, to: temporary)
                } catch {
                    rollBack()
                    throw BatchRenameError.failed(url.lastPathComponent, underlying: error)
                }
                staged.append((url, temporary, url.deletingLastPathComponent().appendingPathComponent(name)))
            }
            for item in staged {
                do {
                    try fileManager.moveItem(at: item.temporary, to: item.final)
                } catch {
                    rollBack()
                    throw BatchRenameError.failed(item.original.lastPathComponent, underlying: error)
                }
                finished.append(item)
            }
            return staged.map { FileChange.moved(from: $0.original, to: $0.final) }
        }.value
    }

    // MARK: Naming

    private static func split(_ name: String, includeExtension: Bool) -> (stem: String, ext: String) {
        let ext = (name as NSString).pathExtension
        // A dot-file like ".gitignore" has no extension to keep, just a name.
        guard !includeExtension, !ext.isEmpty, name != ".\(ext)" else { return (name, "") }
        return ((name as NSString).deletingPathExtension, ext)
    }

    private static func apply(_ rule: BatchRenameRule, to stem: String, index: Int, regex: NSRegularExpression?) -> String {
        switch rule {
        case .replace(let find, let replacement, let caseSensitive, _):
            guard !find.isEmpty else { return stem }
            if let regex {
                let range = NSRange(stem.startIndex..., in: stem)
                return regex.stringByReplacingMatches(in: stem, range: range, withTemplate: replacement)
            }
            return stem.replacingOccurrences(of: find, with: replacement, options: caseSensitive ? [] : [.caseInsensitive])
        case .add(let text, .before):
            return text + stem
        case .add(let text, .after):
            return stem + text
        case .format(let base, let position, let start, let digits):
            let number = String(start + index)
            let counter = String(repeating: "0", count: max(0, digits - number.count)) + number
            switch (base.isEmpty, position) {
            case (true, _): return counter
            case (false, .after): return "\(base) \(counter)"
            case (false, .before): return "\(counter) \(base)"
            }
        case .changeCase(.lowercase):
            return stem.lowercased()
        case .changeCase(.uppercase):
            return stem.uppercased()
        case .changeCase(.titleCase):
            return stem.capitalized
        }
    }

    private static func key(_ folder: URL, _ name: String) -> String {
        folder.standardizedFileURL.path + "/" + name.lowercased()
    }
}
