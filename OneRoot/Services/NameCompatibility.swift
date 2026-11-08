import Foundation

/// One item whose name a destination can't store, and the name it would
/// get instead.
struct NameFix: Identifiable, Sendable, Equatable {
    let source: URL
    let newName: String
    var id: URL { source }
    var oldName: String { source.lastPathComponent }
}

/// Everything in one copy/move whose name the destination can't store —
/// asked about once, before anything is copied.
struct NameFixRequest: Identifiable, Sendable {
    let id = UUID()
    let fixes: [NameFix]
    let destination: URL
    let isMove: Bool
    /// Stopped looking after this many.
    let isTruncated: Bool
}

enum NameFixAnswer: Sendable, Equatable {
    /// Copy them under the fixed names.
    case rename
    /// Leave them out; copy the rest.
    case skip
    /// Copy nothing.
    case cancel
}

/// #70: Windows-style destinations — SMB shares and FAT/exFAT/NTFS drives
/// — reject names a Mac allows: `\ : * ? " < > |`, control characters,
/// a trailing space or period, and the reserved device names (CON, PRN,
/// AUX, NUL, COM1–9, LPT1–9). A copy there would fail partway through on
/// the first such name. This finds them up front and proposes names that
/// work: each bad character becomes "_", trailing spaces and periods go,
/// and a reserved name gets "_" after it.
///
/// NFS and Mac disks accept all of these, so they're never checked.
enum NameCompatibility {
    /// The file systems that need the check, by `volumeTypeName`.
    static let restrictiveVolumeTypes: Set<String> = ["smbfs", "msdos", "exfat", "ntfs", "cifs"]

    /// The most problems listed (and fixed) for one operation.
    static let limit = 5_000

    private static let invalidCharacters = CharacterSet(charactersIn: "\\:*?\"<>|")
        .union(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(0x1F)))

    private static let reservedNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for number in 1...9 {
            names.insert("COM\(number)")
            names.insert("LPT\(number)")
        }
        return names
    }()

    /// Whether `folder`'s volume restricts names (its nearest existing
    /// folder's, for a destination that doesn't exist yet).
    static func restrictsNames(at folder: URL) -> Bool {
        var probe = folder
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        #if os(Linux)
        guard let type = linuxFileSystemType(atPath: probe.path) else { return false }
        return restrictiveLinuxTypes.contains(type.lowercased())
        #else
        guard let type = try? probe.resourceValues(forKeys: [.volumeTypeNameKey]).volumeTypeName else { return false }
        return restrictiveVolumeTypes.contains(type.lowercased())
        #endif
    }

    #if os(Linux)
    /// The same file systems on Linux, by the type in the mount table.
    /// `fuseblk` is how ntfs-3g (and exfat-fuse) mounts show up.
    static let restrictiveLinuxTypes: Set<String> = ["vfat", "msdos", "exfat", "ntfs", "ntfs3", "fuseblk", "cifs", "smb3", "smbfs"]

    /// The file-system type of the mount `path` is on.
    static func linuxFileSystemType(atPath path: String) -> String? {
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return MountTable.current()?.entry(containing: target)?.type
    }
    #endif

    /// A name such a destination accepts, or `nil` when `name` is fine.
    static func fixedName(for name: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            scalars.append(invalidCharacters.contains(scalar) ? "_" : scalar)
        }
        var fixed = String(scalars)
        while let last = fixed.last, last == " " || last == "." {
            fixed.removeLast()
        }
        if fixed.isEmpty { fixed = "_" }
        let base = (fixed as NSString).deletingPathExtension
        if reservedNames.contains(base.uppercased()) {
            let ext = (fixed as NSString).pathExtension
            fixed = ext.isEmpty ? base + "_" : base + "_." + ext
        }
        return fixed == name ? nil : fixed
    }

    /// Every item in `urls`, and inside the folders among them, whose name
    /// needs fixing — with fixed names that don't collide with anything
    /// else in the same folder. Packages are looked inside too (their
    /// contents get copied). Returns whether it stopped at `limit`.
    static func problems(in urls: [URL], limit: Int = NameCompatibility.limit) -> (fixes: [NameFix], isTruncated: Bool) {
        var fixes: [NameFix] = []

        func visit(_ siblings: [URL]) -> Bool {
            var taken = Set(siblings.map { $0.lastPathComponent.lowercased() })
            for url in siblings {
                if let fixed = fixedName(for: url.lastPathComponent) {
                    let unique = uniqueName(fixed, avoiding: taken)
                    taken.insert(unique.lowercased())
                    fixes.append(NameFix(source: url, newName: unique))
                    if fixes.count >= limit { return false }
                }
                var isDirectory: ObjCBool = false
                let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                if !isLink, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let children = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                        .filter { $0 != ".DS_Store" }
                        .map { url.appendingPathComponent($0) }
                    if !visit(children) { return false }
                }
            }
            return true
        }

        // Top-level items go into the destination side by side.
        let finished = visit(urls)
        return (fixes, !finished)
    }

    /// "name (2).ext", "name (3).ext", … when `name` is already taken
    /// (case-insensitively, as on those file systems).
    static func uniqueName(_ name: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(name.lowercased()) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }
}
