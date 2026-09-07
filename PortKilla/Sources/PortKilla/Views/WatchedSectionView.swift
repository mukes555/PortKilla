import PortKillaCore
import SwiftUI

/// Pinned section at the top of the port list showing every watched port and
/// its live status, including "free", which is the answer people usually
/// opened the app to get.
struct WatchedSectionView: View {
    @ObservedObject var portManager: PortManager
    let metrics: RowMetrics
    let onKillRequest: (PortInfo) -> Void

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    private var gutterWidth: CGFloat { metrics.gutter * scale }
    private var portColumnWidth: CGFloat { metrics.port * scale }
    private var nameCapWidth: CGFloat { metrics.nameCap * scale }
    private var memoryColumnWidth: CGFloat { metrics.memory * scale }
    private var actionColumnWidth: CGFloat { metrics.action * scale }
    private var tileSize: CGFloat { metrics.tile * scale }

    var body: some View {
        let watched = portManager.watchedPorts.sorted()
        VStack(spacing: 0) {
            SectionHeader(title: "Watched", count: watched.count, tint: .yellow) {
                if !portManager.guardedPorts.isEmpty {
                    MascotView(mood: .onGuard, size: 22)
                        .help("A guard is armed: whatever takes a guarded port is auto-killed")
                        .accessibilityLabel("A guard is armed")
                }
            }

            ForEach(watched, id: \.self) { port in
                watchedRow(port: port)
                Divider()
            }
        }
    }

    /// Same columns as the main rows (chevron gutter, port, flexible
    /// process, memory, actions) so the section reads as part of the list
    /// rather than a different table stacked on top of it.
    @ViewBuilder
    private func watchedRow(port: Int) -> some View {
        let active = portManager.activePorts.first { $0.port == port }
        let guarded = portManager.isGuarded(port)

        HStack(spacing: RowMetrics.spacing) {
            Spacer().frame(width: gutterWidth)

            HStack(spacing: 8) {
                IconTile(icon: guarded ? "shield.fill" : "star.fill", tint: guarded ? .orange : .yellow, size: tileSize)
                Text(":\(String(port))")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
            }
            .frame(width: portColumnWidth, alignment: .leading)

            HStack(spacing: 6) {
                if let active {
                    Text(active.processName)
                        .font(.title3.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameCapWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    if active.isExposed {
                        Chip(icon: "wifi.exclamationmark", text: "exposed", tint: .chipOrange)
                    }
                    if let agent = active.agentOwner {
                        AgentChip(agent: agent)
                    }
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("free")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(active?.memoryUsage ?? "")
                .font(.body.monospaced())
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
                    Image(systemName: guarded ? "shield.fill" : "shield")
                        .font(.subheadline)
                        .foregroundColor(guarded ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(guarded ? "Disable guard on port \(port)" : "Guard port \(port)")
                .help(guarded
                      ? "Guard active: anything that takes :\(port) gets auto-killed"
                      : "Guard :\(port): auto-kill anything that takes it")

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
        .padding(.vertical, 8)
        .contextMenu {
            Button("Open in Browser") { Browser.openLocalhost(port: port) }
            Button("Copy Port") { Pasteboard.copy(":\(port)") }
            Divider()
            Button(guarded ? "Remove Guard" : "Guard :\(String(port))") {
                GuardConfirm.toggle(port, in: portManager)
            }
            Button("Stop Watching") { portManager.toggleWatch(port) }
        }
    }
}
