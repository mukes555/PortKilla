import AppKit
import PortNannyCore
import SwiftUI

/// The right-hand pane: everything about one port, with the evidence behind
/// its owner, who is connected, and its history, and the verbs that act on it.
struct WorkbenchInspector: View {
    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case connections = "Connections"
        case agent = "Agent"
        case history = "History"
    }

    let port: PortInfo
    @ObservedObject var portManager: PortManager
    @ObservedObject var history = HistoryManager.shared
    @State var tab: Tab = .overview
    @State var evidence: AttributionEvidence?
    @State var peers: [NativeScanner.Peer] = []
    @State var peek: HTTPPeek.Result?
    @State var peekNote: String?

    var flow: KillFlow { KillFlow(portManager: portManager) }

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
                    case .connections: connectionsPane
                    case .agent: agentPane
                    case .history: historyPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 380)
        .onAppear(perform: reload)
        .onChange(of: port.id) { _ in reload() }
        .onChange(of: port.connections) { _ in loadPeers() }
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
                    AgentChip(agent: agent)
                }
                if let managed = port.managedBy {
                    Chip(icon: managed.kind == .docker ? "shippingbox" : "arrow.triangle.2.circlepath", text: managed.short,
                         tint: managed.kind == .docker ? .chipBlue : .chipOrange)
                }
            }
        }
    }

    /// Kill keeps its word; the rest are icons with tooltips, so six verbs
    /// fit the pane at its narrowest.
    private var actions: some View {
        HStack(spacing: 6) {
            Button { flow.requestKill(port, force: false, killTree: false) } label: { Label("Kill", systemImage: "xmark.circle") }
                .help("Kill (SIGTERM, verified)")
            Button { flow.requestKill(port, force: true, killTree: false) } label: { Image(systemName: "bolt") }
                .help("Force kill (SIGKILL)")
                .accessibilityLabel("Force kill")
            Button { flow.requestKill(port, force: false, killTree: true) } label: { Image(systemName: "arrow.triangle.branch") }
                .help("Kill the process and its children")
                .accessibilityLabel("Kill process tree")
            Button { Browser.openLocalhost(port: port.port) } label: { Image(systemName: "safari") }
                .help("Open localhost:\(port.port) in the browser")
                .accessibilityLabel("Open in browser")
            Button { portManager.toggleWatch(port.port) } label: { Image(systemName: portManager.isWatched(port.port) ? "star.fill" : "star") }
                .help(portManager.isWatched(port.port) ? "Stop watching" : "Watch: be told when it frees up or gets taken")
                .accessibilityLabel(portManager.isWatched(port.port) ? "Unwatch" : "Watch")
            Button { GuardConfirm.toggle(port.port, in: portManager) } label: { Image(systemName: portManager.isGuarded(port.port) ? "shield.fill" : "shield") }
                .help(portManager.isGuarded(port.port) ? "Remove guard" : "Guard: auto-kill whatever takes it")
                .accessibilityLabel(portManager.isGuarded(port.port) ? "Unguard" : "Guard")
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Loading

    private func reload() {
        loadEvidence()
        loadPeers()
        peek = nil
        peekNote = nil
        if portManager.probeLocalServers && port.type.category == .web {
            runPeek()
        }
    }

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

    func loadPeers() {
        let pid = port.pid
        let number = port.port
        guard port.proto == "tcp" else { return peers = [] }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = NativeScanner.peers(of: Int32(pid), localPort: number)
            DispatchQueue.main.async {
                if pid == port.pid { peers = found }
            }
        }
    }

    func runPeek() {
        let number = port.port
        peekNote = "asking…"
        HTTPPeek.probe(port: number) { result in
            DispatchQueue.main.async {
                guard number == port.port else { return }
                switch result {
                case .success(let found):
                    peek = found
                    peekNote = nil
                case .failure(.notHTTP):
                    peek = nil
                    peekNote = "not an HTTP server"
                case .failure(.unreachable(let why)):
                    peek = nil
                    peekNote = why
                }
            }
        }
    }
}
