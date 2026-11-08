import Foundation

/// Figures out how many uncompressed bytes an archive will produce, so
/// `ArchiveService.extract` can report real progress by polling how much
/// has been written so far against this known total. Only zip is
/// supported — the default engine's only format, and `unzip -l` is a
/// stable, always-present system tool with a simple summary line to parse.
/// Anything else (or anything that fails to parse) returns `nil`, and the
/// caller falls back to an indeterminate progress bar.
struct ArchiveSizeInspector {
    private static let unzipPath = "/usr/bin/unzip"

    func totalUncompressedSize(of archiveURL: URL) async -> Int64? {
        guard archiveURL.pathExtension.lowercased() == "zip" else { return nil }
        guard FileManager.default.isExecutableFile(atPath: Self.unzipPath) else { return nil }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.unzipPath)
            process.arguments = ["-l", archiveURL.path]
            process.standardInput = FileHandle.nullDevice

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            guard (try? process.run()) != nil else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return nil }

            return Self.parseTotalBytes(fromUnzipListing: output)
        }.value
    }

    /// `unzip -l`'s last non-empty line looks like
    /// `      169                     4 files` — the total byte count is
    /// its first whitespace-separated token.
    static func parseTotalBytes(fromUnzipListing output: String) -> Int64? {
        guard let lastLine = output.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        guard let firstToken = lastLine.split(separator: " ", omittingEmptySubsequences: true).first else { return nil }
        return Int64(firstToken)
    }
}
