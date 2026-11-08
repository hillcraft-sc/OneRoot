import AppKit

/// OneRoot's own sidebar artwork, in the current theme's colors.
///
/// The artwork is a handful of small flat bitmaps (a folder, a drive, a
/// cloud…), each mostly one color with lighter or darker details. Rather than
/// flatten them to silhouettes, `IconRecolorer` swaps each bitmap's dominant
/// color for the theme's and keeps the details as lighter or darker versions
/// of it, so the icons keep their depth in every theme. A theme whose
/// `recolorsSidebarIcons` is false (macOS Dark) gets the original bitmaps
/// untouched — except the folder, which every theme colors.
@MainActor
enum ThemedIcons {
    enum Role: CaseIterable {
        case folder, drive, volume, network, cloud, pinned, trash, applications

        var assetName: String {
            switch self {
            case .folder: return "folder"
            case .drive: return "boot-volume"
            case .volume: return "usb"
            case .network: return "network"
            case .cloud: return "cloud"
            case .pinned: return "pinned"
            case .trash: return "trash-bin"
            case .applications: return "applications"
            }
        }

        func color(in icons: ThemeIcons) -> ThemeColor {
            switch self {
            case .folder: return icons.folder
            case .drive: return icons.drive
            case .volume: return icons.volume
            case .network: return icons.network
            case .cloud: return icons.cloud
            case .pinned: return icons.pinned
            case .trash: return icons.trash
            case .applications: return icons.applications
            }
        }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(_ role: Role, theme: Theme) -> NSImage? {
        guard let original = NSImage(named: role.assetName) else { return nil }
        // The folder is recolored in every theme, the native ones included
        // (its color is part of what a theme sets); the rest of the native
        // dark artwork stays as drawn.
        guard theme.icons.recolorsSidebarIcons || role == .folder else { return original }

        let target = role.color(in: theme.icons)
        let key = "\(role.assetName)|\(target.hexString)"
        if let cached = cache[key] { return cached }

        // Asked for at twice its point size so the asset's @2x bitmap is the
        // one returned, and it stays sharp. Not looked up in
        // `representations`: images from an asset catalog aren't
        // `NSBitmapImageRep`s, so that found nothing and every icon quietly
        // stayed its original color.
        var proposed = CGRect(x: 0, y: 0, width: original.size.width * 2, height: original.size.height * 2)
        guard let source = original.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let recolored = IconRecolorer.recolor(source, to: target) else {
            return original
        }
        let image = NSImage(cgImage: recolored, size: original.size)
        cache[key] = image
        return image
    }
}

extension ThemedIcons {
    /// The icon a list shows for `url`: the theme's folder for a folder you
    /// can browse into (the bitmap up to 32 points, drawn sharp above),
    /// the system's own icon for files, packages, and volumes.
    static func icon(for url: URL, isFolder: Bool, theme: Theme, size: CGFloat = 16) -> NSImage {
        guard isFolder else { return NSWorkspace.shared.icon(forFile: url.path) }
        if size <= 32, let bitmap = image(.folder, theme: theme) { return bitmap }
        return folder(size: size, color: theme.icons.folder)
    }

    private static var folderIcons: [String: NSImage] = [:]

    /// The theme's folder at any size. The `folder` asset is a 16/32 px
    /// bitmap — fine in a list row, blurry blown up to grid or preview size. This draws the same silhouette in the same
    /// color as a vector instead (the `folder.fill` symbol is close, but
    /// has a front-edge stripe and a shorter tab), so it's sharp at every
    /// size the slider allows.
    static func folder(size: CGFloat, color: ThemeColor) -> NSImage {
        let key = "\(Int(size))|\(color.hexString)"
        if let cached = folderIcons[key] { return cached }
        let icon = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let w = rect.width, h = rect.height
            let path = NSBezierPath(
                roundedRect: NSRect(x: w * 0.06, y: h * 0.24, width: w * 0.88, height: h * 0.62),
                xRadius: w * 0.08,
                yRadius: w * 0.08
            )
            // The tab: rounded top-left corner, sloping down into the body.
            let left = w * 0.06, top = h * 0.12, radius = w * 0.07
            let tab = NSBezierPath()
            tab.move(to: NSPoint(x: left, y: h * 0.32))
            tab.line(to: NSPoint(x: left, y: top + radius))
            tab.appendArc(withCenter: NSPoint(x: left + radius, y: top + radius), radius: radius, startAngle: 180, endAngle: 270, clockwise: false)
            tab.line(to: NSPoint(x: w * 0.38, y: top))
            tab.curve(to: NSPoint(x: w * 0.47, y: h * 0.24), controlPoint1: NSPoint(x: w * 0.43, y: top), controlPoint2: NSPoint(x: w * 0.43, y: h * 0.24))
            tab.line(to: NSPoint(x: w * 0.47, y: h * 0.32))
            tab.close()
            path.append(tab)
            color.nsColor.setFill()
            path.fill()
            return true
        }
        icon.accessibilityDescription = "Folder"
        folderIcons[key] = icon
        return icon
    }

}

/// The pixel work, free of AppKit state so it can be tested on tiny
/// synthetic images.
enum IconRecolorer {
    /// `image` with its typical (median-brightness) color replaced by
    /// `target`, every other pixel recolored by how much lighter or darker
    /// it is than that. Transparency is kept exactly.
    static func recolor(_ image: CGImage, to target: ThemeColor) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        guard let reference = medianLuma(pixels, count: width * height), reference > 0.01 else { return context.makeImage() }

        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }
            // Premultiplied → straight color.
            let red = min(Double(pixels[offset]) / 255 / alpha, 1)
            let green = min(Double(pixels[offset + 1]) / 255 / alpha, 1)
            let blue = min(Double(pixels[offset + 2]) / 255 / alpha, 1)
            let ratio = luma(red, green, blue) / reference

            func channel(_ target: Double) -> Double {
                // Darker than the dominant color: the theme color, dimmed.
                // Lighter: the theme color, brightened toward white.
                let value = ratio <= 1 ? target * ratio : target + (1 - target) * min(1, ratio - 1)
                return min(max(value, 0), 1)
            }
            pixels[offset] = UInt8((channel(target.red) * alpha * 255).rounded())
            pixels[offset + 1] = UInt8((channel(target.green) * alpha * 255).rounded())
            pixels[offset + 2] = UInt8((channel(target.blue) * alpha * 255).rounded())
        }
        return context.makeImage()
    }

    private static func luma(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// The median luma of the opaque pixels — the icon's "typical" color,
    /// as opposed to its shading and details; that median pixel is what
    /// becomes the theme color exactly.
    ///
    /// Not the most common *exact* color, which this used to be: a flat
    /// shape beats a gradient there, because a gradient's pixels spread
    /// over many slightly different colors even when it covers most of the
    /// icon. The Applications icon (a blue gradient with a small flat white
    /// "A") was recolored around its white, leaving most of it a muddy dark
    /// tint — and which one won could flip with the tiniest change in how
    /// the asset was decoded. A median has no such cliff, and no ties to
    /// break (a two-tone icon with equal areas just lands on one tone).
    private static func medianLuma(_ pixels: UnsafePointer<UInt8>, count: Int) -> Double? {
        var lumas: [Double] = []
        lumas.reserveCapacity(count)
        for index in 0..<count {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= 0.94 else { continue }
            lumas.append(luma(
                min(Double(pixels[offset]) / 255 / alpha, 1),
                min(Double(pixels[offset + 1]) / 255 / alpha, 1),
                min(Double(pixels[offset + 2]) / 255 / alpha, 1)
            ))
        }
        guard !lumas.isEmpty else { return nil }
        lumas.sort()
        return lumas[lumas.count / 2]
    }
}
