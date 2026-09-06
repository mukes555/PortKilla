import AppKit
import PortKillaCore
import SwiftUI

/// The right-hand pane: everything about one port, with the evidence behind
/// its owner and its history, and the verbs that act on it.
struct WorkbenchInspector: View {
    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case agent = "Agent"
        case history = "History"
    }

    let port: PortInfo
    @ObservedObject var portManager: PortManager
    @ObservedObject private var history = HistoryManager.shared
    @State private var tab: Tab = .overview
    @State private var evidence: AttributionEvidence?

    private var flow: KillFlow { KillFlow(portManager: portManager) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actions
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    switch tab {
                    case .overview: overview
                    case .agent: agentPane
                    case .history: historyPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 380)
        .onAppear(perform: loadEvidence)
        .onChange(of: port.id) { _ in loadEvidence() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: port.type.icon)
                    .font(.title2)
                    .foregroundColor(Color(nsColor: port.type.color))
                Text(":\(String(port.port))")
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                Text(port.processName)
                    .font(.title3)
                    .lineLimit(1)
                Spacer()
            }
            HStack(spacing: 6) {
                if port.isExposed { Chip(icon: "wifi.exclamationmark", text: "exposed", tint: .chipOrange) }
                if port.connections > 0 { Chip(icon: "person.2", text: "\(port.connections) clients", tint: .chipBlue) }
                if let agent = port.agentOwner {
                    Chip(icon: agent.sessionEnded ? "moon.zzz" : "sparkles", text: agent.label, tint: agent.isLiveAgentSession ? .chipTeal : .secondary)
                }
                if let managed = port.managedBy {
                    Chip(icon: managed.kind == .docker ? "shippingbox" : "arrow.triangle.2.circlepath", text: managed.short,
                         tint: managed.kind == .docker ? .chipBlue : .chipOrange)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { flow.requestKill(port, force: false, killTree: false) } label: { Label("Kill", systemImage: "xmark.circle") }
            Button { flow.requestKill(port, force: true, killTree: false) } label: { Label("Force", systemImage: "bolt") }
                .help("SIGKILL")
            Button { flow.requestKill(port, force: false, killTree: true) } label: { Label("Tree", systemImage: "arrow.triangle.branch") }
                .help("Kill the process and its children")
            Button { Browser.openLocalhost(port: port.port) } label: { Label("Open", systemImage: "safari") }
            Button { portManager.toggleWatch(port.port) } label: {
                Label(portManager.isWatched(port.port) ? "Unwatch" : "Watch", systemImage: portManager.isWatched(port.port) ? "star.fill" : "star")
            }
            Button { GuardConfirm.toggle(port.port, in: portManager) } label: {
                Label(portManager.isGuarded(port.port) ? "Unguard" : "Guard", systemImage: "shield")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var overview: some View {
        Group {
            DetailRow(label: "PID", value: "\(port.pid)")
            DetailRow(label: "User", value: port.user)
            DetailRow(label: "Type", value: port.type.rawValue)
            DetailRow(label: "Bind", value: (port.bindAddress ?? "?") + (port.isExposed ? " (all interfaces)" : ""))
            DetailRow(label: "Proto", value: port.proto.uppercased())
            DetailRow(label: "Clients", value: port.connections == 0 ? "none connected" : "\(port.connections) connected")
            DetailRow(label: "Memory", value: port.memoryUsage)
            DetailRow(label: "CPU", value: String(format: "%.1f%%", port.cpuPercent))
            if let age = port.age { DetailRow(label: "Age", value: age) }
            if let project = port.projectPath ?? port.projectName { DetailRow(label: "Project", value: project) }
            if let container = port.containerName { DetailRow(label: "Container", value: container) }
            if let managed = port.managedBy {
                DetailRow(label: "Managed", value: "\(managed.label); \(managed.consequence)")
                if let command = managed.stopCommand { DetailRow(label: "Stop with", value: command) }
            }
            DetailRow(label: "Command", value: port.command)
            Button("Copy command") { Pasteboard.copy(port.command) }
                .controlSize(.small)
        }
    }

    private var agentPane: some View {
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

    private var historyPane: some View {
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// The ancestry walk is cheap (a handful of processes); the owner itself
    /// stays the scanner's, which judged it against the whole table.
    private func loadEvidence() {
        let pid = port.pid
        DispatchQueue.global(qos: .userInitiated).async {
            let table = ProcessTable.ancestry(of: pid)
            let found = AgentAttribution.explain(pid: pid, in: table)
            DispatchQueue.main.async {
                if pid == port.pid { evidence = found }
            }
        }
    }
}
