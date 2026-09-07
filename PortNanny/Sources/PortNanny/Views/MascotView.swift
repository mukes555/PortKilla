import AppKit
import SwiftUI

/// The quokka. Draws the artwork from the bundle (Contents/Resources/
/// quokka-<mood>.png, copied from PortNanny/assets/mascot by scripts/build.sh)
/// and a friendly stand-in when a file is missing.
struct MascotView: View {
    enum Mood: String {
        case happy
        case sleepy
        case onGuard = "guard"

        var symbol: String {
            switch self {
            case .happy: return "face.smiling"
            case .sleepy: return "moon.zzz"
            case .onGuard: return "hand.raised"
            }
        }
    }

    let mood: Mood
    var size: CGFloat = 96

    private static var cache: [String: NSImage] = [:]

    /// Loaded once per mood: the header draws it on every render.
    static func artwork(for mood: Mood) -> NSImage? {
        if let cached = cache[mood.rawValue] { return cached }
        let loaded = load(mood)
        if let loaded { cache[mood.rawValue] = loaded }
        return loaded
    }

    /// Height over width of the head box. A fifth taller than the ear span
    /// puts the chin inside the box and the neck fade on the collar; a square
    /// (aspect 1) stops under the mouth, which is the round shape the menu
    /// bar traces.
    static let headAspect: CGFloat = 1.2

    /// The head alone, ears to chin, for avatars and the menu bar: the
    /// artwork is a full figure and would be a blob at 30 pt. The box comes
    /// from the artwork's own outline, so the ears are never cut.
    static func face(for mood: Mood, aspect: CGFloat = headAspect) -> NSImage? {
        let key = "\(mood.rawValue)-face-\(aspect)"
        if let cached = cache[key] { return cached }
        guard let full = artwork(for: mood),
              let image = full.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let box = headBox(in: image, aspect: aspect),
              let cropped = image.cropping(to: box),
              let softened = fadedAtTheNeck(cropped) else { return nil }
        let face = NSImage(cgImage: softened, size: NSSize(width: box.width, height: box.height))
        cache[key] = face
        return face
    }

    /// The box around the head: its top is the first opaque row (the ear
    /// tips), its sides the widest span of the upper head, and its height
    /// the width times `aspect`. The hand and the mug sit lower and wider,
    /// outside the box.
    static func headBox(in image: CGImage, aspect: CGFloat = headAspect) -> CGRect? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func opaque(_ x: Int, _ row: Int) -> Bool {
            // A bitmap context's memory runs top-down: row 0 is the ear tips.
            pixels[(row * width + x) * 4 + 3] > 128
        }
        guard let top = (0..<height).first(where: { row in (0..<width).contains { opaque($0, row) } }) else { return nil }
        // The upper head only (ears, brow, the shades): further down the
        // waving hand joins the outline and would widen the box.
        let upperRows = top..<min(height, top + height * 18 / 100)
        var left = width
        var right = 0
        for row in upperRows {
            for x in 0..<width where opaque(x, row) {
                left = min(left, x)
                right = max(right, x)
            }
        }
        guard right > left else { return nil }
        let span = CGFloat(right - left)
        // Room on both sides: the cheeks bulge past the ears, and a head
        // that touches the frame reads as cut off.
        let margin = span * 0.08
        let boxWidth = span + margin * 2
        let box = CGRect(x: CGFloat(left) - margin, y: CGFloat(top) - margin, width: boxWidth, height: boxWidth * aspect)
        return box.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// The bottom of the box cuts through the neck; a fade over the last
    /// eighth makes that a soft edge instead of a line.
    private static func fadedAtTheNeck(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                        colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1]) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.destinationOut)
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: CGFloat(height) / 8), options: [])
        return context.makeImage()
    }

    private static func load(_ mood: Mood) -> NSImage? {
        if let url = Bundle.main.url(forResource: "quokka-\(mood.rawValue)", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #if DEBUG
        // A bare SwiftPM binary has no bundle; renders point at the folder.
        if let directory = ProcessInfo.processInfo.environment["PORTNANNY_MASCOT_DIR"] {
            return NSImage(contentsOfFile: "\(directory)/quokka-\(mood.rawValue).png")
        }
        #endif
        return nil
    }

    var body: some View {
        if let image = Self.artwork(for: mood) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("PortNanny's quokka, \(mood.rawValue)")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: mood.symbol)
                    .font(.system(size: size * 0.45, weight: .regular))
                    .foregroundColor(.accentColor)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
