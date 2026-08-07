#!/usr/bin/env swift
// Renders PortKilla logo banner candidates (yellow bolt on dark, matching the
// app icon). Usage:  swift scripts/make_logo.swift <output-dir>

import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

let darkTop = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
let darkBottom = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func boltImage(pointSize: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.systemYellow]))
    return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
}

func drawCard(size: NSSize, radius: CGFloat) {
    let rect = NSRect(origin: .zero, size: size)
    let card = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(starting: darkTop, ending: darkBottom)?.draw(in: card, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    card.lineWidth = 3
    card.stroke()
}

func withYellowGlow(radius: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.systemYellow.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = radius
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func wordmark(portSize: CGFloat) -> NSAttributedString {
    let font = roundedFont(size: portSize, weight: .heavy)
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: "Port", attributes: [.font: font, .foregroundColor: NSColor.white]))
    text.append(NSAttributedString(string: "Killa", attributes: [.font: font, .foregroundColor: NSColor.systemYellow]))
    return text
}

func savePNG(_ image: NSImage, name: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    let url = outputDir.appendingPathComponent(name)
    try! data.write(to: url)
    print("✅ \(url.path)")
}

// Variant A — bolt left of the two-tone wordmark, tagline underneath
func variantA() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    let mark = wordmark(portSize: 210)
    let markSize = mark.size()
    guard let bolt = boltImage(pointSize: 230) else { return }
    let gap: CGFloat = 60
    let totalWidth = bolt.size.width + gap + markSize.width
    let startX = (size.width - totalWidth) / 2

    withYellowGlow(radius: 60) {
        bolt.draw(in: NSRect(x: startX, y: (size.height - bolt.size.height) / 2 + 40,
                             width: bolt.size.width, height: bolt.size.height))
    }
    mark.draw(at: NSPoint(x: startX + bolt.size.width + gap, y: (size.height - markSize.height) / 2 + 40))

    let tagline = NSAttributedString(
        string: "See every port. Kill any process. Instantly.",
        attributes: [.font: roundedFont(size: 56, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 80))

    image.unlockFocus()
    savePNG(image, name: "logo_a.png")
}

// Variant B — the bolt IS the separator: Port⚡Killa
func variantB() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    let font = roundedFont(size: 230, weight: .heavy)
    let port = NSAttributedString(string: "Port", attributes: [.font: font, .foregroundColor: NSColor.white])
    let killa = NSAttributedString(string: "Killa", attributes: [.font: font, .foregroundColor: NSColor.white])
    guard let bolt = boltImage(pointSize: 210) else { return }

    let gap: CGFloat = 28
    let totalWidth = port.size().width + gap + bolt.size.width + gap + killa.size().width
    var x = (size.width - totalWidth) / 2
    let textY = (size.height - port.size().height) / 2 + 40

    port.draw(at: NSPoint(x: x, y: textY))
    x += port.size().width + gap
    withYellowGlow(radius: 60) {
        bolt.draw(in: NSRect(x: x, y: (size.height - bolt.size.height) / 2 + 40,
                             width: bolt.size.width, height: bolt.size.height))
    }
    x += bolt.size.width + gap
    killa.draw(at: NSPoint(x: x, y: textY))

    let tagline = NSAttributedString(
        string: "The macOS menu bar port manager",
        attributes: [.font: roundedFont(size: 56, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 80))

    image.unlockFocus()
    savePNG(image, name: "logo_b.png")
}

// Variant C — compact: app-icon squircle + wordmark, slim card
func variantC() {
    let size = NSSize(width: 2400, height: 480)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 64)

    // Mini app icon
    let iconSide: CGFloat = 300
    let mark = wordmark(portSize: 190)
    let markSize = mark.size()
    let gap: CGFloat = 70
    let totalWidth = iconSide + gap + markSize.width
    let startX = (size.width - totalWidth) / 2
    let iconRect = NSRect(x: startX, y: (size.height - iconSide) / 2, width: iconSide, height: iconSide)

    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: iconSide * 0.225, yRadius: iconSide * 0.225)
    NSGradient(starting: darkTop.blended(withFraction: 0.25, of: .white) ?? darkTop, ending: darkBottom)?
        .draw(in: squircle, angle: -90)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()

    if let bolt = boltImage(pointSize: 160) {
        withYellowGlow(radius: 40) {
            bolt.draw(in: NSRect(x: iconRect.midX - bolt.size.width / 2,
                                 y: iconRect.midY - bolt.size.height / 2,
                                 width: bolt.size.width, height: bolt.size.height))
        }
    }

    mark.draw(at: NSPoint(x: startX + iconSide + gap, y: (size.height - markSize.height) / 2))

    image.unlockFocus()
    savePNG(image, name: "logo_c.png")
}

// Variant D — terminal aesthetic: monospace wordmark with a cursor block
func variantD() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    let font = NSFont.monospacedSystemFont(ofSize: 200, weight: .heavy)
    let mark = NSMutableAttributedString()
    mark.append(NSAttributedString(string: "Port", attributes: [.font: font, .foregroundColor: NSColor.white]))
    mark.append(NSAttributedString(string: "Killa", attributes: [.font: font, .foregroundColor: NSColor.systemYellow]))
    let markSize = mark.size()

    // Blinking-cursor block after the name
    let cursorWidth: CGFloat = 90
    let totalWidth = markSize.width + 30 + cursorWidth
    let startX = (size.width - totalWidth) / 2
    let textY = (size.height - markSize.height) / 2 + 50
    mark.draw(at: NSPoint(x: startX, y: textY))

    withYellowGlow(radius: 30) {
        NSColor.systemYellow.setFill()
        NSRect(x: startX + markSize.width + 30, y: textY + 20, width: cursorWidth, height: markSize.height * 0.72).fill()
    }

    let tagline = NSAttributedString(
        string: "$ portkilla kill 3000  ⚡ freed",
        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 54, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.5)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 80))

    image.unlockFocus()
    savePNG(image, name: "logo_d.png")
}

// Variant E — the bolt replaces the "i" in Killa: PortK⚡lla
func variantE() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    let font = roundedFont(size: 240, weight: .heavy)
    let left = NSMutableAttributedString()
    left.append(NSAttributedString(string: "Port", attributes: [.font: font, .foregroundColor: NSColor.white]))
    left.append(NSAttributedString(string: "K", attributes: [.font: font, .foregroundColor: NSColor.systemYellow]))
    let right = NSAttributedString(string: "lla", attributes: [.font: font, .foregroundColor: NSColor.systemYellow])

    guard let bolt = boltImage(pointSize: 150) else { return }
    let gap: CGFloat = 12
    let totalWidth = left.size().width + gap + bolt.size.width + gap + right.size().width
    var x = (size.width - totalWidth) / 2
    let textY = (size.height - left.size().height) / 2 + 20

    left.draw(at: NSPoint(x: x, y: textY))
    x += left.size().width + gap
    // Bolt sits on the baseline like a letter
    withYellowGlow(radius: 45) {
        bolt.draw(in: NSRect(x: x, y: textY + 58, width: bolt.size.width, height: bolt.size.height))
    }
    x += bolt.size.width + gap
    right.draw(at: NSPoint(x: x, y: textY))

    image.unlockFocus()
    savePNG(image, name: "logo_e.png")
}

// Variant F — neon: yellow outline glow on near-black
func variantF() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    let card = NSBezierPath(roundedRect: rect, xRadius: 72, yRadius: 72)
    NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.05, alpha: 1).setFill()
    card.fill()
    NSColor.systemYellow.withAlphaComponent(0.25).setStroke()
    card.lineWidth = 4
    card.stroke()

    let font = roundedFont(size: 250, weight: .heavy)
    let mark = NSAttributedString(string: "PortKilla", attributes: [
        .font: font,
        .foregroundColor: NSColor.clear,
        .strokeColor: NSColor.systemYellow,
        .strokeWidth: 2.6
    ])
    let markSize = mark.size()
    guard let bolt = boltImage(pointSize: 190) else { return }
    let gap: CGFloat = 50
    let totalWidth = bolt.size.width + gap + markSize.width
    let startX = (size.width - totalWidth) / 2

    withYellowGlow(radius: 70) {
        bolt.draw(in: NSRect(x: startX, y: (size.height - bolt.size.height) / 2,
                             width: bolt.size.width, height: bolt.size.height))
        mark.draw(at: NSPoint(x: startX + bolt.size.width + gap, y: (size.height - markSize.height) / 2))
    }

    image.unlockFocus()
    savePNG(image, name: "logo_f.png")
}

// Variant G — giant dim bolt watermark behind a centered wordmark
func variantG() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    if let watermark = boltImage(pointSize: 560) {
        watermark.draw(
            in: NSRect(x: (size.width - watermark.size.width) / 2,
                       y: (size.height - watermark.size.height) / 2,
                       width: watermark.size.width, height: watermark.size.height),
            from: .zero, operation: .sourceOver, fraction: 0.10
        )
    }

    let mark = wordmark(portSize: 240)
    let markSize = mark.size()
    mark.draw(at: NSPoint(x: (size.width - markSize.width) / 2, y: (size.height - markSize.height) / 2 + 30))

    let tagline = NSAttributedString(
        string: "Kill dev ports. Instantly.",
        attributes: [.font: roundedFont(size: 56, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 75))

    image.unlockFocus()
    savePNG(image, name: "logo_g.png")
}

// MARK: - Custom drawing helpers

/// A sharp, hand-drawn lightning bolt (not the SF Symbol) — classic 6-point zigzag.
func customBoltPath(in rect: NSRect) -> NSBezierPath {
    let points: [(CGFloat, CGFloat)] = [
        (0.62, 1.00), (0.10, 0.42), (0.40, 0.42), (0.28, 0.00), (0.90, 0.56), (0.52, 0.56)
    ]
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + points[0].0 * rect.width, y: rect.minY + points[0].1 * rect.height))
    for point in points.dropFirst() {
        path.line(to: NSPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height))
    }
    path.close()
    return path
}

/// Deterministic pseudo-random (so regenerated banners are identical).
struct LCG {
    var seed: UInt64 = 42
    mutating func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 10000) / 10000
    }
}

func renderText(_ attributed: NSAttributedString) -> NSImage {
    let size = attributed.size()
    let image = NSImage(size: size)
    image.lockFocus()
    attributed.draw(at: .zero)
    image.unlockFocus()
    return image
}

// Variant H — story art: a bolt cracks ":3000" in half
func variantH() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    let portText = renderText(NSAttributedString(
        string: ":3000",
        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 290, weight: .heavy),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.92)]
    ))
    let textSize = portText.size
    let centerX = size.width / 2
    let textY: CGFloat = 210
    let shift: CGFloat = 26

    // Top and bottom halves, sheared apart by the strike
    let topHalf = NSRect(x: 0, y: textSize.height / 2, width: textSize.width, height: textSize.height / 2)
    let bottomHalf = NSRect(x: 0, y: 0, width: textSize.width, height: textSize.height / 2)
    portText.draw(
        in: NSRect(x: centerX - textSize.width / 2 + shift, y: textY + textSize.height / 2,
                   width: textSize.width, height: textSize.height / 2),
        from: topHalf, operation: .sourceOver, fraction: 1.0
    )
    portText.draw(
        in: NSRect(x: centerX - textSize.width / 2 - shift, y: textY,
                   width: textSize.width, height: textSize.height / 2),
        from: bottomHalf, operation: .sourceOver, fraction: 1.0
    )

    // The bolt striking through the crack, tilted
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: centerX, yBy: textY + textSize.height / 2)
    transform.rotate(byDegrees: -14)
    transform.concat()
    let boltRect = NSRect(x: -85, y: -230, width: 170, height: 460)
    withYellowGlow(radius: 55) {
        NSGradient(starting: .systemYellow, ending: NSColor.orange)?
            .draw(in: customBoltPath(in: boltRect), angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()

    // Spark shards around the impact
    var rng = LCG(seed: 7)
    NSColor.systemYellow.withAlphaComponent(0.85).setFill()
    for _ in 0..<10 {
        let angle = rng.next() * 2 * .pi
        let distance = 150 + rng.next() * 160
        let sx = centerX + cos(angle) * distance
        let sy = textY + textSize.height / 2 + sin(angle) * distance * 0.55
        let sparkSize = 6 + rng.next() * 12
        NSBezierPath(ovalIn: NSRect(x: sx, y: sy, width: sparkSize, height: sparkSize)).fill()
    }

    let mark = wordmark(portSize: 96)
    let markSize = mark.size()
    mark.draw(at: NSPoint(x: (size.width - markSize.width) / 2, y: 52))

    image.unlockFocus()
    savePNG(image, name: "logo_h.png")
}

// Variant I — circuit traces converging on a custom bolt
func variantI() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()
    drawCard(size: size, radius: 72)

    // Circuit traces: right-angled lines with solder pads at the ends
    let traces: [[NSPoint]] = [
        [NSPoint(x: 120, y: 520), NSPoint(x: 480, y: 520), NSPoint(x: 560, y: 440)],
        [NSPoint(x: 80, y: 160), NSPoint(x: 400, y: 160), NSPoint(x: 500, y: 260)],
        [NSPoint(x: 200, y: 340), NSPoint(x: 520, y: 340)],
        [NSPoint(x: 2280, y: 500), NSPoint(x: 1950, y: 500), NSPoint(x: 1870, y: 420)],
        [NSPoint(x: 2320, y: 140), NSPoint(x: 2000, y: 140), NSPoint(x: 1910, y: 240)],
        [NSPoint(x: 2200, y: 320), NSPoint(x: 1890, y: 320)],
    ]
    NSColor.systemYellow.withAlphaComponent(0.18).setStroke()
    for trace in traces {
        let path = NSBezierPath()
        path.move(to: trace[0])
        for point in trace.dropFirst() { path.line(to: point) }
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.stroke()

        NSColor.systemYellow.withAlphaComponent(0.30).setFill()
        NSBezierPath(ovalIn: NSRect(x: trace[0].x - 10, y: trace[0].y - 10, width: 20, height: 20)).fill()
    }

    // Custom bolt centerpiece
    let boltRect = NSRect(x: size.width / 2 - 480 - 110, y: 170, width: 220, height: 330)
    withYellowGlow(radius: 60) {
        NSGradient(starting: .systemYellow, ending: NSColor.orange)?
            .draw(in: customBoltPath(in: boltRect), angle: -90)
    }

    let mark = wordmark(portSize: 210)
    let markSize = mark.size()
    mark.draw(at: NSPoint(x: size.width / 2 - 480 + 160, y: (size.height - markSize.height) / 2))

    image.unlockFocus()
    savePNG(image, name: "logo_i.png")
}

// Variant J — glitch: sliced wordmark with chromatic ghost copies
func variantJ() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.06, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 72, yRadius: 72).fill()

    let font = NSFont.monospacedSystemFont(ofSize: 240, weight: .heavy)
    func mark(_ color: NSColor, yellowTail: Bool) -> NSImage {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Port", attributes: [.font: font, .foregroundColor: color]))
        text.append(NSAttributedString(string: "Killa", attributes: [
            .font: font, .foregroundColor: yellowTail ? NSColor.systemYellow : color
        ]))
        return renderText(text)
    }

    let main = mark(.white, yellowTail: true)
    let textSize = main.size
    let origin = NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)

    // Chromatic ghosts
    mark(NSColor.systemRed.withAlphaComponent(0.45), yellowTail: false)
        .draw(at: NSPoint(x: origin.x - 14, y: origin.y + 6), from: .zero, operation: .sourceOver, fraction: 1)
    mark(NSColor.systemCyan.withAlphaComponent(0.45), yellowTail: false)
        .draw(at: NSPoint(x: origin.x + 14, y: origin.y - 6), from: .zero, operation: .sourceOver, fraction: 1)

    // Main wordmark drawn as horizontal slices with jitter
    let offsets: [CGFloat] = [6, -16, 4, 22, -8, 12, -20, 8, -5, 15]
    let sliceHeight = textSize.height / CGFloat(offsets.count)
    for (index, offset) in offsets.enumerated() {
        let sourceRect = NSRect(x: 0, y: CGFloat(index) * sliceHeight, width: textSize.width, height: sliceHeight)
        let destination = NSRect(x: origin.x + offset, y: origin.y + CGFloat(index) * sliceHeight,
                                 width: textSize.width, height: sliceHeight)
        main.draw(in: destination, from: sourceRect, operation: .sourceOver, fraction: 1)
    }

    let tagline = NSAttributedString(
        string: "// no port survives",
        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 52, weight: .medium),
                     .foregroundColor: NSColor.systemYellow.withAlphaComponent(0.6)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 70))

    image.unlockFocus()
    savePNG(image, name: "logo_j.png")
}

// Variant K — modern product banner: radial glow, grain, custom bolt
func variantK() {
    let size = NSSize(width: 2400, height: 640)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    let card = NSBezierPath(roundedRect: rect, xRadius: 72, yRadius: 72)
    NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).setFill()
    card.fill()

    // Radial glow rising from behind the lockup
    card.addClip()
    let glowCenter = NSPoint(x: size.width / 2, y: 120)
    NSGradient(colors: [
        NSColor.systemYellow.withAlphaComponent(0.22),
        NSColor.orange.withAlphaComponent(0.08),
        .clear
    ])?.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 900, options: [])

    // Film grain (deterministic)
    var rng = LCG(seed: 99)
    NSColor.white.withAlphaComponent(0.025).setFill()
    for _ in 0..<3500 {
        NSRect(x: rng.next() * size.width, y: rng.next() * size.height, width: 2.2, height: 2.2).fill()
    }

    // Lockup: custom bolt + wordmark
    let mark = wordmark(portSize: 230)
    let markSize = mark.size()
    let boltRect = NSRect(x: 0, y: 0, width: 210, height: 320)
    let gap: CGFloat = 55
    let totalWidth = boltRect.width + gap + markSize.width
    let startX = (size.width - totalWidth) / 2

    withYellowGlow(radius: 65) {
        NSGradient(starting: .systemYellow, ending: NSColor.orange)?
            .draw(in: customBoltPath(in: boltRect.offsetBy(dx: startX, dy: (size.height - boltRect.height) / 2 + 25)), angle: -90)
    }
    mark.draw(at: NSPoint(x: startX + boltRect.width + gap, y: (size.height - markSize.height) / 2 + 25))

    let tagline = NSAttributedString(
        string: "See every port. Kill any process. Instantly.",
        attributes: [.font: roundedFont(size: 54, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.5)]
    )
    let tagSize = tagline.size()
    tagline.draw(at: NSPoint(x: (size.width - tagSize.width) / 2, y: 72))

    image.unlockFocus()
    savePNG(image, name: "logo_k.png")
}

variantA()
variantB()
variantC()
variantD()
variantE()
variantF()
variantG()
variantH()
variantI()
variantJ()
variantK()
