import AppKit
import PortKillaCore

/// The menu bar's images: the app icon itself, dimmed while nothing is
/// listening; a monochrome quokka cut from the artwork, a template that
/// follows the bar's light or dark look; and a vector face for a bare debug
/// binary that has neither.
enum MenuBarGlyph {
    static let pointSize: CGFloat = 18
    private static var cache: [String: NSImage] = [:]
    private static var silhouette: NSImage?

    static func image(_ icon: PortManager.MenuBarIcon, active: Bool) -> NSImage {
        let key = "\(icon.rawValue)-\(active)"
        if let cached = cache[key] { return cached }
        let image: NSImage
        switch icon {
        case .color: image = colorIcon(active: active)
        case .mono: image = monoIcon(active: active)
        }
        cache[key] = image
        return image
    }

    /// The app icon as the bundle carries it, at menu bar size; the face
    /// from the artwork when there is no bundle.
    static func colorIcon(active: Bool) -> NSImage {
        guard let source = appIcon() ?? faceInCircle() else { return quokka(filled: active) }
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: active ? 1 : 0.45)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = description(active: active)
        return image
    }

    /// The quokka's head as a template: fur is the shape, the shades and the
    /// mouth are holes, so the face still reads at 18 points.
    static func monoIcon(active: Bool) -> NSImage {
        guard let mask = silhouetteFromArtwork() else { return quokka(filled: active) }
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            mask.draw(in: rect, from: .zero, operation: .sourceOver, fraction: active ? 1 : 0.5)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(active: active)
        return image
    }

    private static func description(active: Bool) -> String {
        active ? "PortKilla, active ports" : "PortKilla, no active ports"
    }

    private static func appIcon() -> NSImage? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    }

    private static func faceInCircle() -> NSImage? {
        guard let face = MascotView.face(for: .happy) else { return nil }
        let side: CGFloat = 64
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            face.draw(in: rect)
            return true
        }
    }

    /// Thresholded at 144 px and scaled from there, so the edges come out
    /// smooth instead of jagged. Cut once; only a hit is remembered, since
    /// a test may point at the artwork after the first ask.
    private static func silhouetteFromArtwork() -> NSImage? {
        if let silhouette { return silhouette }
        guard let face = MascotView.face(for: .happy),
              let source = face.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 144
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // An oval, like the avatar's circle but trimmed on the right: the
        // crop's edges hold a waving hand and a mug, noise at 18 points.
        context.addEllipse(in: CGRect(x: 2, y: 2, width: side - 14, height: side - 4))
        context.clip()
        context.draw(source, in: fitted(source, in: CGFloat(side)))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for index in 0..<(side * side) {
            let pixel = pixels + index * 4
            let alpha = Int(pixel[3])
            let luminance = (Int(pixel[0]) * 299 + Int(pixel[1]) * 587 + Int(pixel[2]) * 114) / 1000
            // Fur (opaque and not dark) is the shape; the shades and the
            // mouth (near black) and the background (clear) are holes.
            let solid = alpha > 128 && luminance > alpha * 18 / 100
            pixel[0] = 0
            pixel[1] = 0
            pixel[2] = 0
            pixel[3] = solid ? 255 : 0
        }
        guard let mask = context.makeImage() else { return nil }
        let image = NSImage(cgImage: mask, size: NSSize(width: side, height: side))
        silhouette = image
        return image
    }

    /// The head centred in a square, whole.
    private static func fitted(_ image: CGImage, in side: CGFloat) -> CGRect {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        if aspect >= 1 {
            let height = side / aspect
            return CGRect(x: 0, y: (side - height) / 2, width: side, height: height)
        }
        let width = side * aspect
        return CGRect(x: (side - width) / 2, y: 0, width: width, height: side)
    }

    // MARK: - Vector fallback

    /// A drawn face (head, ears, shades, a smile) for builds without the
    /// artwork. Filled means ports are active, outlined means none.
    static func quokka(filled: Bool, size: CGFloat = pointSize) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(filled: filled, unit: size / 18)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(active: filled)
        return image
    }

    /// The face on an 18-point grid; `unit` scales it to the image.
    private static func draw(filled: Bool, unit s: CGFloat) {
        let head = NSBezierPath(ovalIn: NSRect(x: 2.5 * s, y: 1.5 * s, width: 13 * s, height: 12 * s))
        let leftEar = NSBezierPath(ovalIn: NSRect(x: 1.5 * s, y: 10.5 * s, width: 5.5 * s, height: 5.5 * s))
        let rightEar = NSBezierPath(ovalIn: NSRect(x: 11 * s, y: 10.5 * s, width: 5.5 * s, height: 5.5 * s))
        let shades = NSBezierPath()
        shades.append(NSBezierPath(roundedRect: NSRect(x: 3.6 * s, y: 7.2 * s, width: 4.6 * s, height: 3.2 * s), xRadius: 1.4 * s, yRadius: 1.4 * s))
        shades.append(NSBezierPath(roundedRect: NSRect(x: 9.8 * s, y: 7.2 * s, width: 4.6 * s, height: 3.2 * s), xRadius: 1.4 * s, yRadius: 1.4 * s))
        shades.append(NSBezierPath(rect: NSRect(x: 8 * s, y: 8.3 * s, width: 2 * s, height: 1 * s)))
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 7 * s, y: 4.6 * s))
        smile.curve(to: NSPoint(x: 11 * s, y: 4.6 * s), controlPoint1: NSPoint(x: 8 * s, y: 3.2 * s), controlPoint2: NSPoint(x: 10 * s, y: 3.2 * s))
        smile.lineWidth = 1.1 * s

        NSColor.black.set()
        if filled {
            for part in [leftEar, rightEar, head] { part.fill() }
            cutOut {
                shades.fill()
                smile.stroke()
            }
            return
        }
        let stroke = 1.3 * s
        for ear in [leftEar, rightEar] {
            ear.lineWidth = stroke
            ear.stroke()
        }
        // The head sits in front of the ears: clear its inside first, so the
        // ear outlines stop at its edge.
        cutOut { head.fill() }
        head.lineWidth = stroke
        head.stroke()
        shades.fill()
    }

    /// Draws with the parts erased from what is already there.
    private static func cutOut(_ body: () -> Void) {
        let context = NSGraphicsContext.current
        context?.compositingOperation = .destinationOut
        body()
        context?.compositingOperation = .sourceOver
    }
}
