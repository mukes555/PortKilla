import AppKit
import PortKillaCore
import SwiftUI

/// The confirmations every kill goes through, whichever window asked: the
/// confirm-before-kill setting, the agent warning, connected clients, and
/// supervised listeners. Views keep only their selection bookkeeping.
struct KillFlow {
    let portManager: PortManager

    /// True when a kill (or a supervisor's stop) was dispatched.
    @discardableResult
    func requestKill(_ port: PortInfo, force: Bool, killTree: Bool) -> Bool {
        let warnings = Self.warnings(for: port)
        // A supervisor would undo a plain kill; Docker's backend is never the target.
        if let managed = port.managedBy, !force || managed.kind == .docker {
            return requestManagedStop(port, managed: managed, warnings: warnings)
        }
        let message = (["This will terminate '\(port.processName)' (PID \(port.pid))."] + warnings).joined(separator: "\n\n")
        let confirmed = confirmIfNeeded(
            title: "Kill Process on :\(port.port)?",
            message: message,
            owner: port.agentOwner,
            alwaysAsk: !warnings.isEmpty
        )
        guard confirmed else { return false }
        portManager.killPort(port, force: force, killTree: killTree)
        return true
    }

    /// What every kill dialog must say, whichever verb it ends up offering:
    /// the live agent session, the connected clients, the lease.
    static func warnings(for port: PortInfo) -> [String] {
        var lines: [String] = []
        if case .warn(let reason) = KillDecision.forHuman(target: port.agentOwner) {
            lines.append(reason)
        }
        if port.connections > 0 {
            lines.append("\(port.connections) client\(port.connections == 1 ? " is" : "s are") connected to it right now.")
        }
        if case .warn(let reason) = KillDecision.forReservation(caller: nil, reservation: port.reservation, asAgent: false) {
            lines.append(reason)
        }
        return lines
    }

    func requestKillTest(_ test: TestProcessInfo, force: Bool = false) {
        let confirmed = confirmIfNeeded(
            title: "Kill \(test.processName)?",
            message: "This will terminate '\(test.processName)' (PID \(test.pid)).",
            owner: test.agentOwner
        )
        guard confirmed else { return }
        portManager.killTestProcess(test, force: force)
    }

    func requestKillChild(_ child: PortInfo.ProcessInfo) {
        if portManager.confirmBeforeKill {
            let confirmed = runKillConfirmation(
                title: "Kill \(child.name)?",
                message: "This will terminate '\(child.name)' (PID \(child.pid))."
            )
            guard confirmed else { return }
        }
        portManager.killProcess(pid: child.pid, name: child.name)
    }

    /// Bulk kills list every target and count the agent sessions among them.
    /// Supervised servers are left out: a plain kill would not last, and
    /// their own verb is offered one at a time.
    func requestKillAll(_ targets: [PortInfo], label: String) {
        let (killable, supervised) = Self.bulkTargets(targets, isProtected: portManager.isProtectedProcessName)
        if killable.isEmpty {
            let why = supervised.isEmpty ? "There are no unprotected processes here." : Self.skippedNote(supervised)
            KillConfirm.inform(title: "Nothing to Kill", message: why)
            return
        }
        let processList = killable.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: killable.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let skipped = supervised.isEmpty ? "" : "\n\n" + Self.skippedNote(supervised)
        let confirmed = KillConfirm.run(
            title: "\(label): \(killable.count) process\(killable.count == 1 ? "" : "es")?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\(skipped)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killPorts(killable)
        }
    }

    /// What a bulk kill may take and what it must leave: protected names
    /// are out, and so are supervised servers, whose own verb is offered one
    /// at a time because a plain kill would not last.
    static func bulkTargets(_ targets: [PortInfo], isProtected: (String) -> Bool) -> (killable: [PortInfo], supervised: [PortInfo]) {
        let unprotected = targets.filter { !isProtected($0.processName) }
        return (unprotected.filter { $0.managedBy == nil }, unprotected.filter { $0.managedBy != nil })
    }

    static func skippedNote(_ supervised: [PortInfo]) -> String {
        let list = supervised.map { ":\($0.port) (\($0.managedBy?.label ?? "supervised"))" }.joined(separator: ", ")
        return "Skipped, because a supervisor would restart them: \(list). Stop those one at a time so the right verb is used."
    }

    func requestKillAllTests() {
        let testProcesses = portManager.activeTests
        let killable = testProcesses.filter { !portManager.isProtectedProcessName($0.processName) }
        if killable.isEmpty {
            KillConfirm.inform(
                title: "No Test Processes Found",
                message: testProcesses.isEmpty ? "There are no active test processes to kill." : "All active test processes are protected."
            )
            return
        }
        let processList = killable.map { "• \($0.processName) (PID: \($0.pid))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: killable.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let confirmed = KillConfirm.run(
            title: "Kill \(killable.count) Test Processes?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killTestProcesses(killable)
        }
    }

    /// Honours confirm-before-kill, and always asks when another agent's
    /// live session owns the target, whatever the setting says.
    private func confirmIfNeeded(title: String, message: String, owner: AgentOwner?, alwaysAsk: Bool = false) -> Bool {
        let decision = KillDecision.forHuman(target: owner)
        guard portManager.confirmBeforeKill || decision != .allow || alwaysAsk else { return true }

        var text = message
        if case .warn(let reason) = decision {
            text += "\n\n\(reason)"
        }
        return runKillConfirmation(title: title, message: text)
    }

    func runKillConfirmation(title: String, message: String) -> Bool {
        KillConfirm.run(title: title, message: message) { dontAskAgain in
            if dontAskAgain { portManager.confirmBeforeKill = false }
        }
    }

    // MARK: - Managed runtimes

    enum ManagedChoice {
        case stop
        case killAnyway
        case cancel
    }

    /// Offers the verb that frees the port for real. True when something
    /// was dispatched. `warnings` are the lines every kill dialog shows.
    func requestManagedStop(_ port: PortInfo, managed: ManagedRuntime, warnings: [String] = []) -> Bool {
        switch managed.kind {
        case .reloader:
            let lines = ["It supervises '\(port.processName)' (PID \(port.pid)) on :\(port.port) and \(managed.consequence). PortKilla stops the supervisor and everything under it."] + warnings
            let confirmed = runKillConfirmation(title: "Stop \(managed.label)?", message: lines.joined(separator: "\n\n"))
            guard confirmed else { return false }
            portManager.stopSupervisor(of: port)
            return true
        case .pm2, .launchd, .docker:
            switch runManagedChoice(port, managed: managed, warnings: warnings) {
            case .stop:
                portManager.stopManaged(port)
                return true
            case .killAnyway:
                portManager.killPort(port)
                return true
            case .cancel:
                return false
            }
        }
    }

    private func runManagedChoice(_ port: PortInfo, managed: ManagedRuntime, warnings: [String]) -> ManagedChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "'\(port.processName)' on :\(port.port) is \(managed.label)"
        var buttons: [ManagedChoice] = []
        var lines: [String]
        if let arguments = managed.stopArguments, let command = managed.stopCommand {
            lines = ["A plain kill would not last: \(managed.consequence).", "PortKilla can run `\(command)` instead."]
            alert.addButton(withTitle: "Stop via \(arguments[0])")
            buttons.append(.stop)
        } else {
            lines = ["A plain kill would not last: \(managed.consequence). Find the container with `docker ps`."]
        }
        alert.informativeText = (lines + warnings).joined(separator: "\n\n")
        // Docker's backend is never the thing to kill.
        if managed.kind != .docker {
            alert.addButton(withTitle: "Kill anyway")
            buttons.append(.killAnyway)
        }
        alert.addButton(withTitle: "Cancel")
        buttons.append(.cancel)

        let response = alert.runModal()
        let index = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        return buttons.indices.contains(index) ? buttons[index] : .cancel
    }
}
