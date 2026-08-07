import SwiftUI
import AppKit

/// Captures a new global shortcut: press the combination, done.
struct HotKeyRecorderView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss
    @State private var monitor: Any?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 14) {
            DetailTitleBar(onClose: { dismiss() })

            Image(systemName: "keyboard")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("Press the new shortcut")
                .font(.headline)
            Text("Must include ⌘, ⌥, or ⌃ · current: \(appDelegate.hotkeyDisplay) · Esc to cancel")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button("Reset to ⌥⌘P") {
                appDelegate.resetHotKey()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 320, height: 240)
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            dismiss()
            return true
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let requiresRealModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard requiresRealModifier, let key = event.charactersIgnoringModifiers, !key.isEmpty else {
            errorText = "Include at least ⌘, ⌥, or ⌃"
            return true
        }

        let display = GlobalHotKey.displayString(for: flags, key: key)
        let registered = appDelegate.setHotKey(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: GlobalHotKey.carbonModifiers(from: flags),
            display: display
        )

        if registered {
            dismiss()
        } else {
            errorText = "\(display) couldn't be registered — likely taken by the system"
        }
        return true
    }
}
