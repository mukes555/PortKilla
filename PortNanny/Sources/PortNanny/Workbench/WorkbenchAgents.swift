import PortNannyCore
import SwiftUI

/// Ports grouped by the agent session that started them: live sessions,
/// ended ones (safe to clean up), editor terminals, and the unclaimed.
struct WorkbenchAgents: View {
    @ObservedObject var portManager: PortManager
    @Binding var selection: String?

    private var sessions: [WorkbenchModel.AgentSession] {
        WorkbenchModel.agentSessions(from: portManager.visiblePorts)
    }

    private var orphaned: [PortInfo] {
        WorkbenchModel.orphaned(portManager.visiblePorts)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !orphaned.isEmpty {
                HStack {
                    Image(systemName: "moon.zzz").foregroundColor(.secondary)
                    Text("\(orphaned.count) server\(orphaned.count == 1 ? "" : "s") left behind by ended sessions")
                        .font(.caption)
                    Spacer()
                    Button("Clean up") {
                        KillFlow(portManager: portManager).requestKillAll(orphaned, label: "Clean up ended sessions")
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }
            if sessions.isEmpty {
                WorkbenchEmpty(icon: "sparkles", text: "No listening ports")
            } else {
                List(sessions) { session in
                    card(for: session)
                        .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }

    private func card(for session: WorkbenchModel.AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: session.kind))
                    .foregroundColor(tint(for: session.kind))
                Text(session.title).font(.headline)
                if session.kind == .live {
                    Chip(text: "running", tint: .chipTeal)
                } else if session.kind == .ended {
                    Chip(text: "ended", tint: .secondary)
                }
                Spacer()
                Text("\(session.ports.count) port\(session.ports.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(session.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            PortChipRow(ports: session.ports, selection: $selection)
            HStack(spacing: 8) {
                Button(session.kind == .ended ? "Clean up (\(session.ports.count))" : "Stop all (\(session.ports.count))") {
                    KillFlow(portManager: portManager).requestKillAll(session.ports, label: "Stop \(session.title)",
                                                                     confirmTitle: session.kind == .ended ? "Clean Up" : "Stop All")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func icon(for kind: WorkbenchModel.AgentSession.Kind) -> String {
        switch kind {
        case .live: return "sparkles"
        case .ended: return "moon.zzz"
        case .editor: return "terminal"
        case .unattributed: return "questionmark.circle"
        }
    }

    private func tint(for kind: WorkbenchModel.AgentSession.Kind) -> Color {
        switch kind {
        case .live: return .chipTeal
        default: return .secondary
        }
    }
}
