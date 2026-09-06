import SwiftUI
import Foundation
import AppKit

// MARK: - Keyboard handling and kill flows
extension PortListView {

    func installKeyMonitorIfNeeded() {
        // Pinned-window copies skip the monitor — two instances would
        // double-handle every shortcut.
        guard installsKeyMonitor else { return }
        // The popover can re-show without a matching onDisappear;
        // guard so shortcuts never stack duplicate monitors.
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    /// Returns true when the event was handled (and should be consumed).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Don't hijack keys while a sheet or alert has its own focus.
        guard activeSheet == nil else { return false }

        let hasCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53: // Esc: clear the search first, then close
            if !searchText.isEmpty {
                searchText = ""
            } else {
                appDelegate.closePopover()
            }
            return true
        case 125: // ↓
            moveSelection(by: 1)
            return true
        case 126: // ↑
            moveSelection(by: -1)
            return true
        case 124: // → expands the tree — but only when not editing search text
            if searchText.isEmpty, let port = selectedPort, port.children?.isEmpty == false {
                expandedIds.insert(port.id)
                return true
            }
            return false
        case 123: // ←
            if searchText.isEmpty, let port = selectedPort {
                expandedIds.remove(port.id)
                return true
            }
            return false
        case 36: // ⏎ kills the selection; ⌘⏎ force kills
            if filter == .tests, let test = selectedTest {
                requestKillTest(test, force: hasCommand)
                return true
            }
            if let port = selectedPort {
                requestKill(port, force: hasCommand, killTree: false)
                return true
            }
            return false
        default:
            break
        }

        guard hasCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "r":
            portManager.refresh(showToast: true)
            return true
        case "k":
            if filter == .tests {
                killAllTests()
            } else {
                killAllDev()
            }
            return true
        case "o":
            if let port = selectedPort {
                Browser.openLocalhost(port: port.port)
                return true
            }
            return false
        case "c":
            // Only steal ⌘C from the search field when there's nothing to copy there.
            if searchText.isEmpty, let port = selectedPort {
                Pasteboard.copy("\(port.port)")
                portManager.showToast("Copied \(port.port)")
                return true
            }
            return false
        case "q":
            NSApplication.shared.terminate(nil)
            return true
        default:
            return false
        }
    }

    func moveSelection(by offset: Int) {
        let ids = visibleIdsInOrder
        guard !ids.isEmpty else { return }

        guard let current = selectedId, let index = ids.firstIndex(of: current) else {
            selectedId = offset >= 0 ? ids.first : ids.last
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        selectedId = ids[next]
    }

    /// Single entry point for killing a port: applies the confirm-before-kill
    /// setting (with a "don't ask again" checkbox) and then delegates.
    func requestKill(_ port: PortInfo, force: Bool, killTree: Bool) {
        let confirmed = confirmIfNeeded(
            title: "Kill Process on :\(port.port)?",
            message: "This will terminate '\(port.processName)' (PID \(port.pid)).",
            owner: port.agentOwner
        )
        guard confirmed else { return }
        portManager.killPort(port, force: force, killTree: killTree)
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

    /// Honours confirm-before-kill, and always asks when another agent's
    /// live session owns the target, whatever the setting says.
    private func confirmIfNeeded(title: String, message: String, owner: AgentOwner?) -> Bool {
        let decision = KillDecision.forHuman(target: owner)
        guard portManager.confirmBeforeKill || decision != .allow else { return true }

        var text = message
        if case .warn(let reason) = decision {
            text += "\n\n\(reason)"
        }
        return runKillConfirmation(title: title, message: text)
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

    func runKillConfirmation(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            portManager.confirmBeforeKill = false
        }
        return confirmed
    }

    func killAllDev() {
        let devPorts = portManager.visiblePorts.filter {
            $0.type.category == .web && !portManager.isProtectedProcessName($0.processName)
        }

        if devPorts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Dev Servers Found"
            alert.informativeText = "There are no unprotected dev server processes to kill."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = devPorts.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: devPorts.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let confirmed = KillConfirm.run(
            title: "Kill \(devPorts.count) Dev Server\(devPorts.count == 1 ? "" : "s")?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killPorts(devPorts)
        }
    }

    func killAllTests() {
        let testProcesses = portManager.activeTests
        let killableTests = testProcesses.filter { !portManager.isProtectedProcessName($0.processName) }

        if killableTests.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Test Processes Found"
            alert.informativeText = testProcesses.isEmpty
                ? "There are no active test processes to kill."
                : "All active test processes are protected."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = killableTests.map { "• \($0.processName) (PID: \($0.pid))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: killableTests.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let confirmed = KillConfirm.run(
            title: "Kill \(killableTests.count) Test Processes?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killTestProcesses(killableTests)
        }
    }
}
