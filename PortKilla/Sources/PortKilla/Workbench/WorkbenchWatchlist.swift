import PortKillaCore
import SwiftUI

/// Watched and guarded ports with their live status, and a way to add one.
struct WorkbenchWatchlist: View {
    @ObservedObject var portManager: PortManager
    @Binding var selection: String?
    @State private var newPortText = ""

    private var ports: [Int] {
        portManager.watchedPorts.union(portManager.guardedPorts).sorted()
    }

    private var newPort: Int? {
        guard let port = Int(newPortText.trimmingCharacters(in: .whitespaces)), PortManager.isValidPortNumber(port) else { return nil }
        return port
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Port number", text: $newPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button("Watch") { add { portManager.toggleWatch($0) } }
                    .disabled(newPort == nil)
                Button("Guard") { add { GuardConfirm.toggle($0, in: portManager) } }
                    .disabled(newPort == nil)
                Spacer()
            }
            .controlSize(.small)
            .padding(10)
            Divider()
            if ports.isEmpty {
                WorkbenchEmpty(icon: "star", text: "Watch a port to be told when it frees up; guard one to keep it free")
            } else {
                List(ports, id: \.self) { port in
                    row(for: port)
                        .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }

    private func add(_ action: (Int) -> Void) {
        guard let port = newPort else { return }
        action(port)
        newPortText = ""
    }

    private func row(for port: Int) -> some View {
        let occupant = portManager.activePorts.first { $0.port == port }
        return HStack(spacing: 10) {
            Button {
                portManager.toggleWatch(port)
            } label: {
                Image(systemName: portManager.isWatched(port) ? "star.fill" : "star")
                    .foregroundColor(portManager.isWatched(port) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(portManager.isWatched(port) ? "Stop watching" : "Watch")

            Button {
                GuardConfirm.toggle(port, in: portManager)
            } label: {
                Image(systemName: portManager.isGuarded(port) ? "shield.fill" : "shield")
                    .foregroundColor(portManager.isGuarded(port) ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(portManager.isGuarded(port) ? "Remove guard" : "Guard: auto-kill whatever takes it")

            Text(":\(String(port))")
                .font(.system(.body, design: .monospaced))
                .frame(width: 70, alignment: .leading)

            if let occupant {
                Button {
                    selection = occupant.id
                } label: {
                    HStack(spacing: 6) {
                        Text(occupant.processName).fontWeight(.medium)
                        if let agent = occupant.agentOwner {
                            Chip(icon: agent.sessionEnded ? "moon.zzz" : "sparkles", text: agent.label,
                                 tint: agent.isLiveAgentSession ? .chipTeal : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                if portManager.isGuarded(port), portManager.guardHasStruckOut(on: port) {
                    Chip(icon: "pause", text: "guard paused", tint: .chipOrange)
                        .help("The guard gave up on this port after repeated respawns")
                }
                Spacer()
                Button("Kill") {
                    KillFlow(portManager: portManager).requestKill(occupant, force: false, killTree: false)
                }
                .controlSize(.small)
            } else {
                Text("free")
                    .foregroundColor(.green)
                Spacer()
            }
        }
    }
}
