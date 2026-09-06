import SwiftUI
import AppKit

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum Browser {
    static func openLocalhost(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One confirmation dialog for every kill, so copy, button order, and style
/// can't drift across the (many) call sites. Returns true if the user confirms.
enum KillConfirm {
    /// `dontAskAgain` adds the suppression checkbox and receives its state
    /// when the user confirms.
    @discardableResult
    static func run(title: String, message: String, confirmTitle: String = "Kill",
                    dontAskAgain: ((Bool) -> Void)? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: confirmTitle)
        // The most dangerous button in the app should look like one.
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if dontAskAgain != nil {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
        }

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed {
            dontAskAgain?(alert.suppressionButton?.state == .on)
        }
        return confirmed
    }

    /// "Nothing to do" notices, in the same voice as the confirmations.
    static func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Enabling a guard is the one automation that kills without asking, so it
/// always gets an explicit confirmation, wherever it is toggled from.
enum GuardConfirm {
    static func toggle(_ port: Int, in manager: PortManager) {
        if manager.isGuarded(port) {
            manager.toggleGuard(port)
            return
        }
        let confirmed = KillConfirm.run(
            title: "Guard port :\(port)?",
            message: "PortKilla will automatically kill any unprotected process of yours that starts listening on :\(port), and notify you when it does. Servers belonging to a running AI agent session are never auto-killed.",
            confirmTitle: "Guard"
        )
        if confirmed {
            manager.toggleGuard(port)
        }
    }
}

/// One chip style for every inline tag (exposed, agent, project, container,
/// UDP). System colours adapt to light and dark; in light mode the label is
/// darkened so 10pt text stays legible on the pale fill.
struct Chip: View {
    var icon: String? = nil
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let label = colorScheme == .light ? tint.darkened(by: 0.3) : tint
        HStack(spacing: 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(label)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(tint.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(0.35), lineWidth: 0.5))
        .cornerRadius(4)
    }
}

extension Color {
    static let chipTeal = Color(nsColor: .systemTeal)
    static let chipOrange = Color(nsColor: .systemOrange)
    static let chipPurple = Color(nsColor: .systemPurple)
    static let chipBlue = Color(nsColor: .systemBlue)

    func darkened(by fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(self).blended(withFraction: fraction, of: .black) ?? NSColor(self))
    }
}

/// Detects installed code editors so project folders can be opened in them.
enum EditorLauncher {
    struct Editor {
        let name: String
        let appURL: URL
    }

    private static let candidates: [(name: String, bundleId: String)] = [
        ("VS Code", "com.microsoft.VSCode"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Zed", "dev.zed.Zed"),
        ("Sublime Text", "com.sublimetext.4"),
        ("Trae", "com.trae.app"),
    ]

    /// Probed once per launch — installing an editor mid-session is rare.
    static let installed: [Editor] = candidates.compactMap { candidate in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleId)
            .map { Editor(name: candidate.name, appURL: $0) }
    }

    static func open(path: String, with editor: Editor) {
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: editor.appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

struct DetailTitleBar: View {
    let onClose: () -> Void
    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    if isHoveringClose {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }

            Circle()
                .fill(Color.yellow)
                .frame(width: 12, height: 12)
                .opacity(0.7)

            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .opacity(0.7)

            Spacer()
        }
        .padding(.top, 4)
        .padding(.leading, 2)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))
            .cornerRadius(8)
    }
}
