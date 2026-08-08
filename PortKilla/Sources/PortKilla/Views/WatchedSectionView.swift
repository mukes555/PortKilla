import SwiftUI

/// Pinned section at the top of the port list showing every watched port and
/// its live status — including "free", which is the answer users usually
/// opened the app to get.
struct WatchedSectionView: View {
    @ObservedObject var portManager: PortManager
    let onKillRequest: (PortInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WATCHED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))

            ForEach(portManager.watchedPorts.sorted(), id: \.self) { port in
                watchedRow(port: port)
                Divider()
            }
        }
    }

    @ViewBuilder
    private func watchedRow(port: Int) -> some View {
        let active = portManager.activePorts.first { $0.port == port }

        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundColor(.yellow)

            Text(":\(String(port))")
                .font(.system(.body, design: .monospaced))
                .frame(width: 64, alignment: .leading)

            if let active {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(active.processName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(active.memoryUsage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("free")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }

            Spacer()

            if let active {
                Button(action: { onKillRequest(active) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kill process on port \(port)")
                .help("Kill \(active.processName)")
            }

            Button(action: { toggleGuard(port) }) {
                Image(systemName: portManager.isGuarded(port) ? "bolt.shield.fill" : "bolt.shield")
                    .font(.system(size: 11))
                    .foregroundColor(portManager.isGuarded(port) ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(portManager.isGuarded(port) ? "Disable guard on port \(port)" : "Guard port \(port)")
            .help(portManager.isGuarded(port)
                  ? "Guard active: anything that takes :\(port) gets auto-killed"
                  : "Guard :\(port) — auto-kill anything that takes it")

            Button(action: { portManager.toggleWatch(port) }) {
                Image(systemName: "star.slash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop watching port \(port)")
            .help("Stop watching :\(port)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// Enabling a guard is the one automation that kills without asking —
    /// it always gets an explicit confirmation.
    private func toggleGuard(_ port: Int) {
        if portManager.isGuarded(port) {
            portManager.toggleGuard(port)
            return
        }

        let confirmed = KillConfirm.run(
            title: "Guard port :\(port)?",
            message: "PortKilla will automatically kill any unprotected process of yours that starts listening on :\(port), and notify you when it does.",
            confirmTitle: "Guard"
        )
        if confirmed {
            portManager.toggleGuard(port)
        }
    }
}
