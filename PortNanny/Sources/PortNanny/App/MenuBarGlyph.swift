import AppKit
import PortNannyCore

/// The menu bar's images: a monochrome quokka traced from the artwork, a
/// template that follows the bar's light or dark look; the app icon itself,
/// dimmed while nothing is listening; and a vector face for a bare debug
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
        // A vector stand-in is not remembered: the artwork may turn up later
        // (a test pointing at it), and drawing it again is cheap.
        if !image.isVectorFallback { cache[key] = image }
        return image
    }

    /// The app icon as the bundle carries it, at menu bar size; the face
    /// from the artwork when there is no bundle. Rasterised, so the 1024 px
    /// icon file is read once and let go.
    static func colorIcon(active: Bool) -> NSImage {
        guard let source = appIcon() ?? MascotView.face(for: .happy) else { return quokka(filled: active) }
        let image = rasterised(source, alpha: active ? 1 : 0.45)
        image.isTemplate = false
        image.accessibilityDescription = description(active: active)
        return image
    }

    /// The quokka's head as a template: fur is the shape, the shades and the
    /// mouth are holes, so the face still reads at 18 points.
    static func monoIcon(active: Bool) -> NSImage {
        guard let mask = silhouetteFromArtwork() else { return quokka(filled: active) }
        let image = rasterised(mask, alpha: active ? 1 : 0.5)
        image.isTemplate = true
        image.accessibilityDescription = description(active: active)
        return image
    }

    private static func description(active: Bool) -> String {
        active ? "PortNanny, active ports" : "PortNanny, no active ports"
    }

    private static func appIcon() -> NSImage? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    }

    /// An 18 pt image backed by one 36 px bitmap (Retina), drawn from the
    /// source once; the source is not retained.
    static func rasterised(_ source: NSImage, alpha: CGFloat) -> NSImage {
        let pixels = Int(pointSize * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize), from: .zero, operation: .sourceOver, fraction: alpha)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        return image
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
        image.isVectorFallback = true
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

private extension NSImage {
    private static var fallbackKey = 0

    /// Marks the drawn stand-in so the cache can tell it from the artwork.
    var isVectorFallback: Bool {
        get { objc_getAssociatedObject(self, &Self.fallbackKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &Self.fallbackKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
