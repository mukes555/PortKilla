import PortKillaCore
import SwiftUI

/// Watched and guarded ports with their live status, and a way to add one.
struct WorkbenchWatchlist: View {
    @ObservedObject var portManager: PortManager
    @Binding var selection: String?
    @State private var newPortText = ""
    @State private var leases: [Reservation] = []

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
            if ports.isEmpty && leases.isEmpty {
                WorkbenchEmpty(icon: "star", text: "Watch a port to be told when it frees up; guard one to keep it free")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !ports.isEmpty {
                            sectionHeader("WATCHED AND GUARDED")
                            ForEach(ports, id: \.self) { port in
                                row(for: port)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                Divider()
                            }
                        }
                        if !leases.isEmpty {
                            sectionHeader("RESERVED")
                            ForEach(leases) { lease in
                                leaseRow(lease)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadLeases)
        .onReceive(portManager.clock.objectWillChange) { _ in loadLeases() }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
    }

    /// Leases live in the shared store; the cached read is cheap enough per
    /// scan, and the state only changes when the leases did.
    private func loadLeases() {
        let fresh = ReservationStore.shared.recent()
        if fresh != leases { leases = fresh }
    }

    /// "Reserved by Claude Code (session 56034) until 12:30 (8m left), for e2e tests"
    private func leaseRow(_ lease: Reservation) -> some View {
        let occupant = portManager.activePorts.first { $0.port == lease.port }
        return HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundColor(.chipPurple)
            Text(":\(String(lease.port))")
                .font(.system(.body, design: .monospaced))
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(lease.describedHolder) \(lease.expiryDescription())")
                    .font(.callout)
                if let reason = lease.reason {
                    Text(reason).font(.caption).foregroundColor(.secondary)
                }
            }
            if let occupant {
                Button {
                    selection = occupant.id
                } label: {
                    Text("in use by \(occupant.processName)").font(.caption)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Release") {
                _ = ReservationStore.shared.release(port: lease.port, by: nil, force: true)
                loadLeases()
            }
            .controlSize(.small)
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
                            AgentChip(agent: agent)
                        }
                    }
                }
                .buttonStyle(.plain)
                if portManager.isGuarded(port), portManager.guardIsStruckOut(on: port) {
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
