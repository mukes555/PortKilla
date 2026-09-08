import AppKit
import PortNannyCore
import SwiftUI

/// The one thing Return does for the current search text, resolved against
/// the live port list so the bar and the key handler agree.
struct PaletteAction: Equatable {
    enum Kind: Equatable {
        case kill(PortInfo)
        case open(Int)
        case watch(Int, on: Bool)
        case guardPort(Int, on: Bool)
        case command(PaletteQuery.Command)
        case copyFreePort(Int)
        /// Nothing to run; the bar explains why.
        case nothing
    }

    let kind: Kind
    let title: String
    let detail: String?
    let icon: String
    let isDestructive: Bool

    var isRunnable: Bool { kind != .nothing }

    static func resolve(_ query: PaletteQuery, ports: [PortInfo], manager: PortManager) -> PaletteAction? {
        switch query.intent {
        case .none:
            return nil
        case .commands:
            guard let first = query.commandMatches.first else {
                return PaletteAction(kind: .nothing, title: "No command matches", detail: nil, icon: "questionmark", isDestructive: false)
            }
            return PaletteAction(kind: .command(first), title: first.rawValue, detail: nil, icon: first.icon, isDestructive: first == .quit)
        case .freePort(let near):
            // Leases others hold are taken too; no bind probe here, this runs
            // on every render, and the CLI probes when it matters.
            let leased = ReservationStore.shared.recent().filter { !$0.isHeld(by: nil) }.map(\.port)
            let listening = Set(ports.map(\.port)).union(leased)
            guard let free = PortNannyCLI.firstFreePort(prefer: near, range: near...min(near + 999, 65535), listening: listening, probe: false) else {
                return PaletteAction(kind: .nothing, title: "No free port near \(near)", detail: nil, icon: "xmark.circle", isDestructive: false)
            }
            return PaletteAction(kind: .copyFreePort(free), title: ":\(free) is free", detail: "Return copies it", icon: "number", isDestructive: false)
        case .verb(let verb, let port):
            return resolve(verb, port: port, ports: ports, manager: manager)
        }
    }

    private static func resolve(_ verb: PaletteQuery.Verb, port: Int, ports: [PortInfo], manager: PortManager) -> PaletteAction {
        let occupant = ports.first { $0.port == port }
        switch verb {
        case .kill, .free, .stop:
            guard let occupant else {
                return PaletteAction(kind: .nothing, title: ":\(port) is already free", detail: nil, icon: "checkmark.circle", isDestructive: false)
            }
            let owner = occupant.agentOwner.flatMap { $0.isLiveAgentSession ? "owned by \($0.described)" : nil }
            let managed = occupant.managedBy.map { "stops \($0.label)" }
            let verbName = occupant.managedBy == nil ? "Kill" : "Stop"
            return PaletteAction(kind: .kill(occupant), title: "\(verbName) :\(port)",
                                 detail: [occupant.processName + " (PID \(occupant.pid))", owner, managed].compactMap { $0 }.joined(separator: " · "),
                                 icon: "xmark.circle.fill", isDestructive: true)
        case .open:
            return PaletteAction(kind: .open(port), title: "Open localhost:\(port)", detail: occupant?.processName, icon: "safari", isDestructive: false)
        case .watch:
            let on = !manager.isWatched(port)
            return PaletteAction(kind: .watch(port, on: on), title: on ? "Watch :\(port)" : "Stop watching :\(port)",
                                 detail: occupant.map { "in use by \($0.processName)" } ?? "currently free", icon: "star", isDestructive: false)
        case .guard:
            let on = !manager.isGuarded(port)
            return PaletteAction(kind: .guardPort(port, on: on), title: on ? "Guard :\(port)" : "Remove guard on :\(port)",
                                 detail: on ? "auto-kill whatever takes it" : nil, icon: "shield", isDestructive: on)
        }
    }
}

extension PortListView {
    var paletteQuery: PaletteQuery { PaletteQuery.parse(searchText) }

    var paletteAction: PaletteAction? {
        PaletteAction.resolve(paletteQuery, ports: portManager.activePorts, manager: portManager)
    }

    /// True when the query had something to run. `force` carries the Command
    /// key from Return, so a typed `kill 3000` force kills like a selected row
    /// does; the palette bar's own button never forces.
    func runPaletteAction(force: Bool = false) -> Bool {
        guard let action = paletteAction, action.isRunnable else { return false }
        switch action.kind {
        case .kill(let port):
            requestKill(port, force: force, killTree: false)
        case .open(let port):
            Browser.openLocalhost(port: port)
        case .watch(let port, _):
            portManager.toggleWatch(port)
            searchText = ""
        case .guardPort(let port, _):
            GuardConfirm.toggle(port, in: portManager)
            searchText = ""
        case .command(let command):
            perform(command)
        case .copyFreePort(let port):
            Pasteboard.copy("\(port)")
            portManager.showToast("Copied \(port)")
            searchText = ""
        case .nothing:
            return false
        }
        return true
    }

    func perform(_ command: PaletteQuery.Command) {
        searchText = ""
        switch command {
        case .refresh: portManager.refresh(showToast: true)
        case .bulkKill: activeSheet = .bulkKill
        case .pin: appDelegate.togglePinnedWindow()
        case .workbench: appDelegate.openWorkbench()
        case .history: appDelegate.showHistory()
        case .freePort: searchText = "free port"
        case .settings: appDelegate.openSettings()
        case .tour: appDelegate.showTour()
        case .quit: NSApplication.shared.terminate(nil)
        }
    }
}

/// The strip under the search field that says what Return will do.
struct PaletteBar: View {
    let action: PaletteAction
    let commands: [PaletteQuery.Command]
    let onRun: () -> Void
    let onCommand: (PaletteQuery.Command) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if commands.count > 1 {
                commandList
            } else {
                primaryRow
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
    }

    private var primaryRow: some View {
        Button(action: onRun) {
            HStack(spacing: 8) {
                Image(systemName: action.icon)
                    .foregroundColor(action.isDestructive ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                    if let detail = action.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if action.isRunnable {
                    Text("⏎")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isRunnable)
        .accessibilityLabel(action.title)
    }

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(commands.prefix(6))) { command in
                Button(action: { onCommand(command) }) {
                    HStack(spacing: 8) {
                        Image(systemName: command.icon)
                            .frame(width: 14)
                        Text(command.rawValue)
                            .font(.system(size: 12, weight: command == commands.first ? .semibold : .regular))
                        Spacer()
                        if command == commands.first {
                            Text("⏎").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
