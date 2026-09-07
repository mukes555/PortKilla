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
        // A supervisor would undo a plain kill; Docker's backend is never the target.
        if let managed = port.managedBy, !force || managed.kind == .docker {
            return requestManagedStop(port, managed: managed)
        }
        var message = "This will terminate '\(port.processName)' (PID \(port.pid))."
        if port.connections > 0 {
            message += "\n\n\(port.connections) client\(port.connections == 1 ? " is" : "s are") connected to it right now."
        }
        var leased = false
        if case .warn(let reason) = KillDecision.forReservation(caller: nil, reservation: port.reservation, asAgent: false) {
            message += "\n\n\(reason)"
            leased = true
        }
        let confirmed = confirmIfNeeded(
            title: "Kill Process on :\(port.port)?",
            message: message,
            owner: port.agentOwner,
            alwaysAsk: port.connections > 0 || leased
        )
        guard confirmed else { return false }
        portManager.killPort(port, force: force, killTree: killTree)
        return true
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
    func requestKillAll(_ targets: [PortInfo], label: String) {
        let killable = targets.filter { !portManager.isProtectedProcessName($0.processName) }
        if killable.isEmpty {
            KillConfirm.inform(title: "Nothing to Kill", message: "There are no unprotected processes here.")
            return
        }
        let processList = killable.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: killable.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let confirmed = KillConfirm.run(
            title: "\(label): \(killable.count) process\(killable.count == 1 ? "" : "es")?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killPorts(killable)
        }
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
    /// was dispatched.
    func requestManagedStop(_ port: PortInfo, managed: ManagedRuntime) -> Bool {
        switch managed.kind {
        case .reloader:
            let confirmed = runKillConfirmation(
                title: "Stop \(managed.label)?",
                message: "It supervises '\(port.processName)' (PID \(port.pid)) on :\(port.port) and \(managed.consequence). PortKilla stops the supervisor and everything under it."
            )
            guard confirmed else { return false }
            portManager.stopSupervisor(of: port)
            return true
        case .pm2, .launchd, .docker:
            switch runManagedChoice(port, managed: managed) {
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

    private func runManagedChoice(_ port: PortInfo, managed: ManagedRuntime) -> ManagedChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "'\(port.processName)' on :\(port.port) is \(managed.label)"
        var buttons: [ManagedChoice] = []
        if let command = managed.stopCommand {
            alert.informativeText = "A plain kill would not last: \(managed.consequence).\n\nPortKilla can run `\(command)` instead."
            alert.addButton(withTitle: "Stop via \(managed.stopArguments?.first ?? "command")")
            buttons.append(.stop)
        } else {
            alert.informativeText = "A plain kill would not last: \(managed.consequence). Find the container with `docker ps`."
        }
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
