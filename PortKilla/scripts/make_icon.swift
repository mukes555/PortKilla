#!/usr/bin/env swift
// Generates assets/AppIcon.icns: a yellow bolt on a dark rounded-rect,
// following the macOS Big Sur icon grid (content inset within the canvas).
// Run from the PortKilla directory:  swift scripts/make_icon.swift

import AppKit

func drawIcon(canvas: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple's icon grid: the squircle occupies ~82% of the canvas
    let inset = canvas * 0.09
    let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
    )
    gradient?.draw(in: squircle, angle: -90)

    // Subtle inner border
    NSColor.white.withAlphaComponent(0.08).setStroke()
    squircle.lineWidth = canvas * 0.008
    squircle.stroke()

    // The bolt
    let symbolSize = canvas * 0.52
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.systemYellow]))
    guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return image }

    let boltRect = NSRect(
        x: (canvas - bolt.size.width) / 2,
        y: (canvas - bolt.size.height) / 2,
        width: bolt.size.width,
        height: bolt.size.height
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.systemYellow.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = canvas * 0.04
    shadow.set()

    bolt.draw(in: boltRect)
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let assetsDir = projectRoot.appendingPathComponent("assets")
let iconsetDir = assetsDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let master = drawIcon(canvas: 1024)
let sizes = [16, 32, 64, 128, 256, 512]
for size in sizes {
    writePNG(master, to: iconsetDir.appendingPathComponent("icon_\(size)x\(size).png"), pixels: size)
    writePNG(master, to: iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png"), pixels: size * 2)
}

let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", assetsDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetDir)
print("✅ Wrote \(assetsDir.appendingPathComponent("AppIcon.icns").path)")
