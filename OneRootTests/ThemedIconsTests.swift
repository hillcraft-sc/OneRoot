import AppKit
import XCTest
@testable import OneRoot

@MainActor
final class ThemedIconsTests: XCTestCase {
    /// A 4x4 test image: mostly one color, one lighter and one darker pixel,
    /// one fully transparent.
    private func makeImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor(srgbRed: 1, green: 0.44, blue: 0.41, alpha: 1).cgColor) // #FF7069
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(NSColor(white: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1)) // lighter detail
        context.setFillColor(NSColor(srgbRed: 0.5, green: 0.22, blue: 0.2, alpha: 1).cgColor)
        context.fill(CGRect(x: 2, y: 0, width: 1, height: 1)) // darker detail
        return context.makeImage()!
    }

    /// The image's pixels as straight sRGB 0...1 values, read from raw bytes
    /// (drawn once into a known sRGB bitmap) so no color-space conversion
    /// from the reader can color the answer.
    private func pixels(_ image: CGImage) -> [(r: Double, g: Double, b: Double, a: Double)] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (0..<(width * height)).map { index in
            let alpha = Double(bytes[index * 4 + 3]) / 255
            guard alpha > 0 else { return (0, 0, 0, 0) }
            return (Double(bytes[index * 4]) / 255 / alpha, Double(bytes[index * 4 + 1]) / 255 / alpha, Double(bytes[index * 4 + 2]) / 255 / alpha, alpha)
        }
    }

    /// Pixel (x, y) with y counted from the top, as the image is displayed.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        pixels(image)[y * image.width + x]
    }

    func testDominantColorBecomesTheTargetExactly() throws {
        let target = ThemeColor(hex: 0x89B4FA)
        let result = try XCTUnwrap(IconRecolorer.recolor(makeImage(), to: target))

        let p = pixel(result, 3, 3)
        XCTAssertEqual(p.r, target.red, accuracy: 0.01)
        XCTAssertEqual(p.g, target.green, accuracy: 0.01)
        XCTAssertEqual(p.b, target.blue, accuracy: 0.01)
        XCTAssertEqual(p.a, 1, accuracy: 0.01)
    }

    func testShadingIsKeptAsLighterAndDarkerVersionsOfTheTarget() throws {
        let target = ThemeColor(hex: 0x89B4FA)
        let result = try XCTUnwrap(IconRecolorer.recolor(makeImage(), to: target))
        func luma(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Double { 0.299 * p.r + 0.587 * p.g + 0.114 * p.b }

        let normal = luma(pixel(result, 3, 3)), lighter = luma(pixel(result, 1, 3)), darker = luma(pixel(result, 2, 3))
        XCTAssertGreaterThan(lighter, normal)
        XCTAssertLessThan(darker, normal)
    }

    func testTransparencyIsKeptExactly() throws {
        let result = try XCTUnwrap(IconRecolorer.recolor(makeImage(), to: ThemeColor(hex: 0x89B4FA)))

        XCTAssertEqual(pixel(result, 0, 3).a, 0, accuracy: 0.01)
        XCTAssertEqual(pixel(result, 3, 3).a, 1, accuracy: 0.01)
    }

    /// The real sidebar artwork, through the real asset catalog: a themed
    /// role must come back actually recolored, not silently the original.
    func testEveryRealAssetIsRecoloredToItsThemeColor() throws {
        let theme = try XCTUnwrap(ThemeCatalog.theme(withID: "catppuccin-mocha"))
        for role in ThemedIcons.Role.allCases {
            let original = try XCTUnwrap(NSImage(named: role.assetName), "missing asset \(role.assetName)")
            let themed = try XCTUnwrap(ThemedIcons.image(role, theme: theme))
            XCTAssertFalse(themed === original, "\(role.assetName) came back unrecolored")

            var rect = CGRect(origin: .zero, size: themed.size)
            let cg = try XCTUnwrap(themed.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            // The icon's typical (median-brightness) pixel is what becomes the theme
            // color, so the median brightness of the result must be the target's.
            // Holds for flat icons, gradients (the Applications icon), and two-tone
            // ones (the boot volume) alike.
            let expected = role.color(in: theme.icons)
            let opaque = pixels(cg).filter { $0.a > 0.94 }
            XCTAssertFalse(opaque.isEmpty, "\(role.assetName) has no opaque pixels")
            func luma(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.299 * r + 0.587 * g + 0.114 * b }
            let lumas = opaque.map { luma($0.r, $0.g, $0.b) }.sorted()
            XCTAssertEqual(
                lumas[lumas.count / 2], luma(expected.red, expected.green, expected.blue), accuracy: 0.03,
                "\(role.assetName): median brightness isn't the theme color's (\(expected.hexString))"
            )
            // And it's the theme's hue, not the original's: the brightest typical pixels
            // lean toward the target channel by channel.
            let typical = opaque.filter { abs(luma($0.r, $0.g, $0.b) - luma(expected.red, expected.green, expected.blue)) < 0.03 }
            XCTAssertFalse(typical.isEmpty)
            let mean = typical.reduce((r: 0.0, g: 0.0, b: 0.0)) { ($0.r + $1.r, $0.g + $1.g, $0.b + $1.b) }
            let n = Double(typical.count)
            XCTAssertEqual(mean.r / n, expected.red, accuracy: 0.08, "\(role.assetName) red")
            XCTAssertEqual(mean.g / n, expected.green, accuracy: 0.08, "\(role.assetName) green")
            XCTAssertEqual(mean.b / n, expected.blue, accuracy: 0.08, "\(role.assetName) blue")
        }
    }

    func testNativeDarkKeepsTheOriginalArtworkUntouchedExceptTheFolder() throws {
        for role in ThemedIcons.Role.allCases where role != .folder {
            let original = try XCTUnwrap(NSImage(named: role.assetName))
            XCTAssertTrue(ThemedIcons.image(role, theme: ThemeCatalog.nativeDark) === original, "\(role.assetName) should stay as drawn")
        }
        let folder = try XCTUnwrap(NSImage(named: "folder"))
        XCTAssertFalse(ThemedIcons.image(.folder, theme: ThemeCatalog.nativeDark) === folder, "every theme colors the folder")
    }

    /// #41: the macOS folder colors.
    func testMacOSFolderColors() {
        XCTAssertEqual(ThemeCatalog.nativeLight.icons.folder.hexString, "#58232A")
        XCTAssertEqual(ThemeCatalog.nativeDark.icons.folder.hexString, "#C46E79")
    }

    /// The app's red is one color per macOS theme: the toolbar's accent layer
    /// matches the folders.
    func testNativeToolbarAccentMatchesTheFolderColor() {
        for theme in [ThemeCatalog.nativeLight, ThemeCatalog.nativeDark] {
            XCTAssertEqual(theme.icons.toolbarSecondary, theme.icons.folder, "\(theme.displayName)")
        }
    }

    func testTheDarkFolderIsTheSameBurgundyJustLighter() {
        func hueAndSaturation(_ c: ThemeColor) -> (h: Double, s: Double) {
            let color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
            return (Double(color.hueComponent) * 360, Double(color.saturationComponent))
        }
        let light = ThemeCatalog.nativeLight.icons.folder, dark = ThemeCatalog.nativeDark.icons.folder
        XCTAssertEqual(hueAndSaturation(dark).h, hueAndSaturation(light).h, accuracy: 4, "same hue")
        XCTAssertGreaterThan(dark.relativeLuminance, light.relativeLuminance)
        // And it shows on a dark window, which the light burgundy would not (about 1.3:1).
        XCTAssertGreaterThanOrEqual(dark.contrast(with: ThemeColor(hex: 0x2B2B2B)), 3)
        XCTAssertGreaterThanOrEqual(dark.contrast(with: ThemeColor(hex: 0x1E1E1E)), 3)
    }
}

@MainActor
final class ThemedRowViewTests: XCTestCase {
    private func render(_ row: NSTableRowView) -> NSBitmapImageRep {
        let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds)!
        row.cacheDisplay(in: row.bounds, to: rep)
        return rep
    }

    private func centerPixel(_ rep: NSBitmapImageRep) -> (r: Double, g: Double, b: Double, a: Double) {
        let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    func testASelectedRowIsFilledWithTheThemeSelectionColor() {
        let selection = ThemeColor(hex: 0x45475A)
        let row = ThemedRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        row.selectionColor = selection.nsColor
        row.isEmphasized = true
        row.isSelected = true

        let p = centerPixel(render(row))

        XCTAssertEqual(p.r, selection.red, accuracy: 0.02)
        XCTAssertEqual(p.g, selection.green, accuracy: 0.02)
        XCTAssertEqual(p.b, selection.blue, accuracy: 0.02)
        XCTAssertEqual(p.a, 1, accuracy: 0.02)
    }

    func testAnUnselectedRowDrawsNoSelection() {
        let row = ThemedRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        row.selectionColor = ThemeColor(hex: 0x45475A).nsColor

        XCTAssertEqual(centerPixel(render(row)).a, 0, accuracy: 0.02)
    }

    func testSelectionIsDimmerWhenTheWindowIsInactive() {
        let row = ThemedRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        row.selectionColor = ThemeColor(hex: 0x45475A).nsColor
        row.isSelected = true
        row.isEmphasized = false

        XCTAssertLessThan(centerPixel(render(row)).a, 0.9)
    }

    func testAThemedSelectionStopsAppKitFlippingTheTextColor() {
        let row = ThemedRowView()
        row.selectionColor = ThemeColor(hex: 0x45475A).nsColor
        row.isSelected = true
        row.isEmphasized = true

        XCTAssertEqual(row.interiorBackgroundStyle, .normal, "emphasized would flip the cell text to white")
    }

    func testNativeThemesLeaveSelectionToAppKit() {
        let row = ThemedRowView()
        row.isSelected = true
        row.isEmphasized = true

        XCTAssertEqual(row.interiorBackgroundStyle, .emphasized)
    }
}
