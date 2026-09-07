import PortKillaCore
import SwiftUI

// MARK: - The inspector's tabs
extension WorkbenchInspector {

    var overview: some View {
        Group {
            HStack(spacing: 12) {
                trend("CPU", value: String(format: "%.1f%%", port.cpuPercent), series: .cpu, tint: .chipTeal)
                trend("Memory", value: port.memoryUsage, series: .memory, tint: .chipBlue)
            }
            .padding(.bottom, 4)
            DetailRow(label: "PID", value: "\(port.pid)")
            DetailRow(label: "User", value: port.user)
            DetailRow(label: "Type", value: port.type.rawValue)
            DetailRow(label: "Bind", value: (port.bindAddress ?? "?") + (port.isExposed ? " (all interfaces)" : ""))
            DetailRow(label: "Proto", value: port.proto.uppercased())
            DetailRow(label: "Clients", value: port.connections == 0 ? "none connected" : "\(port.connections) connected")
            if let age = port.age { DetailRow(label: "Age", value: age) }
            if let project = port.projectPath ?? port.projectName { DetailRow(label: "Project", value: project) }
            if let container = port.containerName { DetailRow(label: "Container", value: container) }
            if let managed = port.managedBy {
                DetailRow(label: "Managed", value: "\(managed.label); \(managed.consequence)")
                if let command = managed.stopCommand { DetailRow(label: "Stop with", value: command) }
            }
            if let lease = port.reservation {
                DetailRow(label: "Reserved", value: "by \(lease.describedHolder) \(lease.expiryDescription())" + (lease.reason.map { ", for \($0)" } ?? ""))
            }
            if port.type.category == .web {
                webRow
            }
            DetailRow(label: "Command", value: port.command)
            Button("Copy command") { Pasteboard.copy(port.command) }
                .controlSize(.small)
        }
    }

    private func trend(_ label: String, value: String, series: SparklineView.Series, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit())
            }
            SparklineView(metrics: portManager.metrics, pid: port.pid, series: series, tint: tint)
                .frame(height: 28)
            Text("last \(MetricsHistory.capacity) scans").font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// One GET to the server, on request or with the opt-in preference.
    private var webRow: some View {
        HStack(spacing: 8) {
            Text("Web").font(.caption).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
            if let peek {
                Text(peek.summary).font(.system(.body, design: .monospaced)).lineLimit(2)
            } else if let peekNote {
                Text(peekNote).font(.caption).foregroundColor(.secondary)
            } else {
                Text("not asked").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Peek") { runPeek() }
                .controlSize(.small)
                .help("Send one GET to http://127.0.0.1:\(port.port)/ and show the status and title")
        }
    }

    var connectionsPane: some View {
        Group {
            HStack {
                Text(NativeScanner.summary(of: peers)).font(.callout)
                Spacer()
                Button {
                    loadPeers()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            if port.proto != "tcp" {
                Text("UDP sockets have no connections.").font(.caption).foregroundColor(.secondary)
            }
            ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: peer.kind)).foregroundColor(tint(for: peer.kind)).frame(width: 16)
                    Text(peer.label).font(.system(.body, design: .monospaced))
                    Chip(text: peer.kind, tint: tint(for: peer.kind))
                    Spacer()
                }
            }
            if peers.contains(where: { $0.kind != "local" }) {
                Label("Something other than this Mac is connected.", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "local": return "desktopcomputer"
        case "lan": return "wifi"
        default: return "globe"
        }
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "local": return .secondary
        case "lan": return .chipOrange
        default: return .red
        }
    }

    var agentPane: some View {
        Group {
            if let owner = port.agentOwner {
                DetailRow(label: "Owner", value: owner.detail)
                DetailRow(label: "Session", value: owner.sessionId)
                DetailRow(label: "Source", value: owner.source == .declared ? "declared via PORTKILLA_OWNER" : owner.source.rawValue)
                if case .warn(let reason) = KillDecision.forHuman(target: owner) {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if port.containerName != nil || port.type == .docker {
                Text("Docker publishes this port; the container owns it, not whoever launched Docker Desktop.")
                    .font(.caption)
            } else {
                Text("No agent above it, no markers in its environment, nothing declared.")
                    .font(.caption)
            }
            if let evidence {
                Text("Evidence").font(.caption.weight(.semibold)).padding(.top, 6)
                if let declared = evidence.declaredOwner {
                    DetailRow(label: "Declared", value: declared + (evidence.declaredSession.map { " (session \($0))" } ?? ""))
                }
                DetailRow(label: "Ancestry", value: evidence.ancestry.isEmpty ? "reparented to launchd" : evidence.ancestryLine)
                DetailRow(label: "Markers", value: evidence.markers.isEmpty ? "none" : evidence.markersLine)
            }
        }
    }

    var historyPane: some View {
        let events = history.events.filter { $0.port == port.port }
        return Group {
            if events.isEmpty {
                Text("No recorded kills or refusals on :\(String(port.port)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(events) { item in
                HStack(spacing: 8) {
                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Text(item.action.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundColor(item.action == .refused ? .orange : .red)
                    Text(item.processName).font(.caption)
                    if let who = item.killedBy {
                        Text(item.action == .refused ? "refused \(who)" : "by \(who)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
