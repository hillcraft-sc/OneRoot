import Foundation

/// Writes a new file without ever replacing an existing one: the content
/// goes to a scratch file on the same volume first, then is moved into
/// place — and if something has appeared at the destination in the
/// meantime, it's given the next free " (2)" name instead. A failed or
/// cancelled write leaves nothing behind.
enum SafeFileWriter {
    /// Calls `write` with a scratch URL to write to; returns where the file
    /// ended up (`destination`, or a " (2)"-style name next to it).
    static func write(to destination: URL, _ write: (URL) throws -> Void) throws -> URL {
        let fileManager = FileManager.default
        // Some network volumes have no replacement directory; the system
        // temporary folder then works too (the move just becomes a copy).
        let scratchFolder: URL
        if let sameVolume = try? fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
        ) {
            scratchFolder = sameVolume
        } else {
            scratchFolder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: scratchFolder, withIntermediateDirectories: true)
        }
        defer { try? fileManager.removeItem(at: scratchFolder) }
        let scratch = scratchFolder.appendingPathComponent(destination.lastPathComponent)
        try write(scratch)

        var target = FileSystemService.uniqueDestination(for: destination)
        for _ in 0..<5 {
            do {
                // `moveItem` refuses to replace an existing item.
                try fileManager.moveItem(at: scratch, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                target = FileSystemService.uniqueDestination(for: destination)
            }
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
    }
}
