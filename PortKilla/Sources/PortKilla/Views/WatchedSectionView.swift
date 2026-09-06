import SwiftUI

/// Pinned section at the top of the port list showing every watched port and
/// its live status — including "free", which is the answer users usually
/// opened the app to get.
struct WatchedSectionView: View {
    @ObservedObject var portManager: PortManager
    let onKillRequest: (PortInfo) -> Void

    @ScaledMetric(relativeTo: .body) private var gutterWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var portColumnWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var nameCapWidth: CGFloat = 130
    @ScaledMetric(relativeTo: .body) private var memoryColumnWidth: CGFloat = 70
    @ScaledMetric(relativeTo: .body) private var actionColumnWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WATCHED")
                    .font(.caption.weight(.bold))
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

    /// Same columns as the main rows (chevron gutter, 80pt port, flexible
    /// process, 70pt memory, 80pt actions) so the section reads as part of
    /// the list rather than a different table stacked on top of it.
    @ViewBuilder
    private func watchedRow(port: Int) -> some View {
        let active = portManager.activePorts.first { $0.port == port }

        HStack(spacing: 8) {
            Spacer().frame(width: gutterWidth)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text(":\(String(port))")
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: portColumnWidth, alignment: .leading)

            HStack(spacing: 6) {
                if let active {
                    Text(active.processName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameCapWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    if active.isExposed {
                        Chip(icon: "wifi.exclamationmark", text: "exposed", tint: .chipOrange)
                    }
                    if let agent = active.agentOwner {
                        Chip(icon: agent.sessionEnded ? "moon.zzz" : "sparkles", text: agent.name,
                             tint: agent.isLiveAgentSession ? .chipTeal : .secondary)
                            .help(agent.detail)
                    }
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("free")
                        .font(.body.weight(.medium))
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(active?.memoryUsage ?? "")
                .font(.subheadline.monospaced())
                .foregroundColor(.secondary)
                .frame(width: memoryColumnWidth, alignment: .trailing)

            HStack(spacing: 6) {
                if let active {
                    Button(action: { onKillRequest(active) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kill process on port \(port)")
                    .help("Kill \(active.processName)")
                }

                Button(action: { GuardConfirm.toggle(port, in: portManager) }) {
                    Image(systemName: portManager.isGuarded(port) ? "bolt.shield.fill" : "bolt.shield")
                        .font(.subheadline)
                        .foregroundColor(portManager.isGuarded(port) ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(portManager.isGuarded(port) ? "Disable guard on port \(port)" : "Guard port \(port)")
                .help(portManager.isGuarded(port)
                      ? "Guard active: anything that takes :\(port) gets auto-killed"
                      : "Guard :\(port) — auto-kill anything that takes it")

                Button(action: { portManager.toggleWatch(port) }) {
                    Image(systemName: "star.slash")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop watching port \(port)")
                .help("Stop watching :\(port)")
            }
            .frame(width: actionColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Open in Browser") { Browser.openLocalhost(port: port) }
            Button("Copy Port") { Pasteboard.copy(":\(port)") }
            Divider()
            Button(portManager.isGuarded(port) ? "Remove Guard" : "Guard :\(String(port))") {
                GuardConfirm.toggle(port, in: portManager)
            }
            Button("Stop Watching") { portManager.toggleWatch(port) }
        }
    }
}
