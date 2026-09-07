import AppKit
import PortKillaCore

/// The menu bar's template images: the quokka face (head, ears, shades, a
/// smile) drawn as vectors so it stays crisp at 18 pt, and the bolt for
/// people who prefer it. Filled means ports are active, outlined means none.
enum MenuBarGlyph {
    static let pointSize: CGFloat = 18
    private static var cache: [String: NSImage] = [:]

    static func image(_ icon: PortManager.MenuBarIcon, active: Bool) -> NSImage {
        let key = "\(icon.rawValue)-\(active)"
        if let cached = cache[key] { return cached }
        let image: NSImage
        switch icon {
        case .bolt:
            image = NSImage(systemSymbolName: active ? "bolt.fill" : "bolt", accessibilityDescription: "PortKilla") ?? quokka(filled: active)
        case .quokka:
            image = quokka(filled: active)
        }
        cache[key] = image
        return image
    }

    static func quokka(filled: Bool, size: CGFloat = pointSize) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(filled: filled, unit: size / 18)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = filled ? "PortKilla, active ports" : "PortKilla, no active ports"
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
