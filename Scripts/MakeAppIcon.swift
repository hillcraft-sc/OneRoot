#!/usr/bin/env swift
// Builds OneRoot's macOS app icon set from a square source image.
//
//   swift Scripts/MakeAppIcon.swift OneRoot-detail.jpg OneRoot/Resources/Assets.xcassets/AppIcon.appiconset
//
// macOS doesn't round or pad an app icon for you (iOS does), so a full-bleed
// square would show up as a hard-edged square next to every other app's.
// This draws Apple's standard shape instead: the artwork scaled to 824 pt
// inside a 1024 pt canvas (the transparent margin leaves room for the
// shadow), clipped to a rounded square (corner radius 185), with a soft
// drop shadow beneath. Each size in the set is then scaled down from that
// 1024 px master, so they all match.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("usage: MakeAppIcon.swift <square source image> <AppIcon.appiconset folder>")
    exit(1)
}
let outputFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)

func makeContext(_ pixels: Int) -> CGContext {
    CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(url.path)") }
}

// The 1024 px master.
let master: CGImage = {
    let context = makeContext(1024)
    context.interpolationQuality = .high
    let artRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: artRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0.1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(source, in: artRect)
    context.restoreGState()
    return context.makeImage()!
}()

// Every size in the set, as (point size, scale) → pixels.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let context = makeContext(pixels)
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    writePNG(context.makeImage()!, to: outputFolder.appendingPathComponent(name))
}
print("wrote \(outputFolder.path)")
