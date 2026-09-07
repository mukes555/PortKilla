import AppKit
import SwiftUI

/// The quokka. Draws the artwork from the bundle (Contents/Resources/
/// quokka-<mood>.png, copied from PortKilla/assets/mascot by scripts/build.sh)
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

    /// The head alone, ears to chin, for avatars: the artwork is a full
    /// figure and would be a blob at 30 pt.
    static func face(for mood: Mood) -> NSImage? {
        let key = "\(mood.rawValue)-face"
        if let cached = cache[key] { return cached }
        guard let full = artwork(for: mood), let image = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let box = CGRect(x: width * 0.23, y: height * 0.09, width: width * 0.60, height: height * 0.38)
        guard let cropped = image.cropping(to: box) else { return nil }
        let face = NSImage(cgImage: cropped, size: NSSize(width: box.width, height: box.height))
        cache[key] = face
        return face
    }

    private static func load(_ mood: Mood) -> NSImage? {
        if let url = Bundle.main.url(forResource: "quokka-\(mood.rawValue)", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #if DEBUG
        // A bare SwiftPM binary has no bundle; renders point at the folder.
        if let directory = ProcessInfo.processInfo.environment["PORTKILLA_MASCOT_DIR"] {
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
                .accessibilityLabel("PortKilla's quokka, \(mood.rawValue)")
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
