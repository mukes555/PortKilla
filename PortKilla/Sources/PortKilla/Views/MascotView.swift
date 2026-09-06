import AppKit
import SwiftUI

/// The quokka. Draws the artwork when it is in the bundle
/// (Contents/Resources/quokka-<mood>.png, copied from assets/mascot by
/// scripts/build.sh) and a friendly stand-in until then, so the layouts that
/// host it are final before the art is.
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
        guard let url = Bundle.main.url(forResource: "quokka-\(mood.rawValue)", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
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
