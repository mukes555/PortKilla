import AppKit
import PortKillaCore
import SwiftUI

/// The popover sizes on offer: the preference names them, the app knows
/// the points.
extension PortManager.PopoverSize {
    var dimensions: NSSize {
        switch self {
        case .compact: return NSSize(width: 500, height: 600)
        case .regular: return NSSize(width: 580, height: 720)
        case .large: return NSSize(width: 660, height: 840)
        }
    }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }
}

/// The quokka's head: the brand mark wherever the app has room for colour
/// (the popover header, the Workbench sidebar, About). Without the artwork
/// (a bare debug binary) the menu bar glyph stands in.
struct BrandAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        if let face = MascotView.face(for: .happy) {
            Image(nsImage: face)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.14))
                Image(nsImage: MenuBarGlyph.quokka(filled: true, size: size * 0.7))
                    .renderingMode(.template)
                    .foregroundColor(.accentColor)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

/// Wordmark plus one line on what is listening right now.
struct BrandHeader: View {
    let summary: String

    var body: some View {
        HStack(spacing: 10) {
            BrandAvatar(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("PortKilla")
                    .font(.system(size: 15, weight: .bold))
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "19 ports · 3.1GB · 2 agent sessions", or what is known so far.
    static func summary(portCount: Int, memory: String, liveSessions: Int, scanned: Bool) -> String {
        guard scanned else { return "Scanning ports…" }
        guard portCount > 0 else { return "Nothing is listening" }
        var parts = ["\(portCount) port\(portCount == 1 ? "" : "s")", memory]
        if liveSessions > 0 {
            parts.append("\(liveSessions) agent session\(liveSessions == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

/// A rounded, tinted square around a symbol: a port's type at a glance,
/// the same shape in every list.
struct IconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 26

    init(icon: String, tint: Color, size: CGFloat = 26) {
        self.icon = icon
        self.tint = tint
        self.size = size
    }

    init(type: PortInfo.PortType, size: CGFloat = 26) {
        self.init(icon: type.icon, tint: Color(nsColor: type.color), size: size)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.5)
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A list section's name, its accent, and how many rows it holds; the
/// accessory (a guard's quokka, say) sits at the trailing edge.
struct SectionHeader<Accessory: View>: View {
    let title: String
    let count: Int
    let tint: Color
    let accessory: () -> Accessory

    init(title: String, count: Int, tint: Color, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.count = count
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 12)
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
            Text(String(count))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(tint.opacity(0.15))
                .clipShape(Capsule())
                .accessibilityLabel("\(count) rows")
            Spacer()
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, count: Int, tint: Color) {
        self.init(title: title, count: count, tint: tint) { EmptyView() }
    }
}

/// The app icon as the bundle carries it; the avatar when there is no bundle.
struct AppIconView: View {
    var size: CGFloat = 72

    private static let bundleIcon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let icon = Self.bundleIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            BrandAvatar(size: size)
        }
    }
}

/// Column widths shared by the list header, the rows, and the watched rows,
/// so the three stay one table. Views scale them with the text size.
enum RowMetrics {
    static let gutter: CGFloat = 16
    static let port: CGFloat = 96
    static let nameCap: CGFloat = 170
    static let memory: CGFloat = 74
    static let action: CGFloat = 80
    static let tile: CGFloat = 26
    static let spacing: CGFloat = 8
}
