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
    @discardableResult
    static func run(title: String, message: String, confirmTitle: String = "Kill") -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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
