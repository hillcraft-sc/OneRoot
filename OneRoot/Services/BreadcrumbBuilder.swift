import Foundation

/// One clickable piece of the address bar's path, e.g. "Documents".
struct BreadcrumbSegment: Equatable {
    let name: String
    let url: URL
}

/// Splits a folder URL into the address bar's breadcrumb segments, the way
/// Explorer shows "This PC › Local Disk (C:) › Users › …". A path on an
/// external volume starts at that volume ("USB Stick › Photos"), not at
/// `/ › Volumes › USB Stick`; everything else starts at the boot volume,
/// shown by its name ("Macintosh HD") rather than as "/".
enum BreadcrumbBuilder {
    static func segments(
        for url: URL,
        volumeName: (URL) -> String = { FileManager.default.displayName(atPath: $0.path) }
    ) -> [BreadcrumbSegment] {
        // Recents or Shared: one segment, its name.
        if let location = VirtualLocation(url: url) {
            return [BreadcrumbSegment(name: location.title, url: url)]
        }
        let components = url.standardizedFileURL.pathComponents // ["/", "Users", "eric"]
        guard components.first == "/" else { return [] }

        var root = URL(fileURLWithPath: "/", isDirectory: true)
        var rest = Array(components.dropFirst())
        if rest.count >= 2, rest[0] == "Volumes" {
            root = root.appendingPathComponent("Volumes", isDirectory: true).appendingPathComponent(rest[1], isDirectory: true)
            rest = Array(rest.dropFirst(2))
        }

        var segments = [BreadcrumbSegment(name: volumeName(root), url: root)]
        var current = root
        for component in rest {
            current = current.appendingPathComponent(component, isDirectory: true)
            segments.append(BreadcrumbSegment(name: component, url: current))
        }
        return segments
    }
}
