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

    static func artwork(for mood: Mood) -> NSImage? {
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
