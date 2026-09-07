#!/usr/bin/env swift
// Turns the quokka artwork into what the app ships:
//   swift scripts/make_artwork.swift icon <1024.png> <out.icns> [out-1024.png]
//   swift scripts/make_artwork.swift mascot <in.png> <out.png> [height]
// icon: masks the square artwork to the macOS rounded-square shape (824 pt
// of a 1024 canvas, transparent margin) and writes an .icns via iconutil.
// mascot: makes the white studio background transparent by flood-filling
// from the edges (interior whites such as teeth stay), then scales down.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(path)") }
}

func context(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create a \(width)x\(height) context")
    }
    context.interpolationQuality = .high
    return context
}

func scaled(_ image: CGImage, to size: CGSize) -> CGImage {
    let canvas = context(width: Int(size.width), height: Int(size.height))
    canvas.draw(image, in: CGRect(origin: .zero, size: size))
    return canvas.makeImage()!
}

// MARK: - Icon

/// The artwork fills a rounded square of 824/1024 of the canvas, the
/// proportion Apple's own icons use; corners outside it are transparent.
func iconCanvas(_ source: CGImage, canvas: Int) -> CGImage {
    let ctx = context(width: canvas, height: canvas)
    let inset = CGFloat(canvas) * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: CGFloat(canvas) - 2 * inset, height: CGFloat(canvas) - 2 * inset)
    let radius = rect.width * 0.2237
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.draw(source, in: rect)
    return ctx.makeImage()!
}

func makeIcon(source: String, output: String, preview: String?) {
    let image = loadImage(source)
    guard image.width == image.height else { fail("the icon source must be square; got \(image.width)x\(image.height)") }
    let master = iconCanvas(image, canvas: 1024)
    if let preview { writePNG(master, to: preview) }

    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PortNanny-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    let sizes = [16, 32, 128, 256, 512]
    for size in sizes {
        writePNG(scaled(master, to: CGSize(width: size, height: size)), to: iconset.appendingPathComponent("icon_\(size)x\(size).png").path)
        writePNG(scaled(master, to: CGSize(width: size * 2, height: size * 2)), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png").path)
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
    try! iconutil.run()
    iconutil.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
    print("wrote \(output)")
}

// MARK: - Mascot

/// Alpha for a pixel by how close it is to white, so the flood-filled edge
/// fades instead of cutting the fur.
func whiteness(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
    Double(min(r, g, b)) / 255
}

func makeMascot(source: String, output: String, height: Int) {
    let image = loadImage(source)
    let width = image.width, high = image.height
    let ctx = context(width: width, height: high)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: high))
    guard let data = ctx.data else { fail("no pixel data") }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * high * 4)

    // Flood fill from every border pixel through near-white pixels.
    var background = [Bool](repeating: false, count: width * high)
    var queue: [Int] = []
    func isNearWhite(_ index: Int) -> Bool {
        let offset = index * 4
        return whiteness(pixels[offset], pixels[offset + 1], pixels[offset + 2]) >= 0.86
    }
    for x in 0..<width { queue.append(x); queue.append((high - 1) * width + x) }
    for y in 0..<high { queue.append(y * width); queue.append(y * width + width - 1) }
    var head = 0
    while head < queue.count {
        let index = queue[head]
        head += 1
        if background[index] || !isNearWhite(index) { continue }
        background[index] = true
        let x = index % width, y = index / width
        if x > 0 { queue.append(index - 1) }
        if x < width - 1 { queue.append(index + 1) }
        if y > 0 { queue.append(index - width) }
        if y < high - 1 { queue.append(index + width) }
    }

    // Background pixels go transparent; pixels next to the background fade
    // by their whiteness, which anti-aliases the fur edge.
    for index in 0..<(width * high) {
        let offset = index * 4
        var alpha: Double = 1
        if background[index] {
            alpha = 0
        } else {
            let x = index % width, y = index / width
            let neighbours = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            let touchesBackground = neighbours.contains { nx, ny in
                nx >= 0 && ny >= 0 && nx < width && ny < high && background[ny * width + nx]
            }
            if touchesBackground {
                alpha = 1 - whiteness(pixels[offset], pixels[offset + 1], pixels[offset + 2])
                alpha = min(1, max(0, alpha * 1.6))
            }
        }
        // Premultiplied: scale the colour with the alpha.
        for channel in 0..<3 {
            pixels[offset + channel] = UInt8(Double(pixels[offset + channel]) * alpha)
        }
        pixels[offset + 3] = UInt8(alpha * 255)
    }
    let cut = ctx.makeImage()!
    let scale = Double(height) / Double(high)
    let result = scaled(cut, to: CGSize(width: Int(Double(width) * scale), height: height))
    writePNG(result, to: output)
    print("wrote \(output) (\(result.width)x\(result.height))")
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "icon" where arguments.count >= 3:
    makeIcon(source: arguments[1], output: arguments[2], preview: arguments.count > 3 ? arguments[3] : nil)
case "mascot" where arguments.count >= 3:
    makeMascot(source: arguments[1], output: arguments[2], height: arguments.count > 3 ? Int(arguments[3]) ?? 512 : 512)
default:
    fail("usage: make_artwork.swift icon <1024.png> <out.icns> [preview.png] | mascot <in.png> <out.png> [height]")
}
