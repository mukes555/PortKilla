import PortKillaCore
import SwiftUI
import Foundation
import AppKit
import Carbon.HIToolbox

/// Virtual key codes by name (Carbon's constants are Int32; NSEvent's are UInt16).
enum KeyCode {
    static let escape = UInt16(kVK_Escape)
    static let `return` = UInt16(kVK_Return)
    static let upArrow = UInt16(kVK_UpArrow)
    static let downArrow = UInt16(kVK_DownArrow)
    static let leftArrow = UInt16(kVK_LeftArrow)
    static let rightArrow = UInt16(kVK_RightArrow)
}

// MARK: - Keyboard handling and kill flows
extension PortListView {

    func installKeyMonitorIfNeeded() {
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
        // Both the popover and the pinned panel host this view; only the
        // copy whose window is key may act, or every shortcut fires twice.
        // With no key window at all (one just closed) the panel copy still
        // answers, as long as the popover isn't the thing on screen.
        let keyWindow = NSApp.keyWindow
        let pinnedIsKey = keyWindow != nil && keyWindow === appDelegate.pinnedPanel
        if hostedInPinnedWindow {
            let nothingIsKey = keyWindow == nil && !appDelegate.popover.isShown
            guard pinnedIsKey || nothingIsKey else { return false }
        } else {
            guard !pinnedIsKey else { return false }
        }

        let hasCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case KeyCode.escape: // clear the search first, then close
            if !searchText.isEmpty {
                searchText = ""
            } else {
                appDelegate.closePopover()
            }
            return true
        case KeyCode.downArrow:
            moveSelection(by: 1)
            return true
        case KeyCode.upArrow:
            moveSelection(by: -1)
            return true
        case KeyCode.rightArrow: // expands the tree, but only when not editing search text
            if searchText.isEmpty, let port = selectedPort, port.children?.isEmpty == false {
                expandedIds.insert(port.id)
                return true
            }
            return false
        case KeyCode.leftArrow:
            if searchText.isEmpty, let port = selectedPort {
                expandedIds.remove(port.id)
                return true
            }
            return false
        case KeyCode.return: // kills the selection; ⌘⏎ force kills
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
            killAllForCurrentFilter()
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
        var message = "This will terminate '\(port.processName)' (PID \(port.pid))."
        if port.connections > 0 {
            message += "\n\n\(port.connections) client\(port.connections == 1 ? " is" : "s are") connected to it right now."
        }
        let confirmed = confirmIfNeeded(
            title: "Kill Process on :\(port.port)?",
            message: message,
            owner: port.agentOwner,
            alwaysAsk: port.connections > 0
        )
        guard confirmed else { return }
        moveSelectionOff(port.id)
        portManager.killPort(port, force: force, killTree: killTree)
    }

    /// The killed row disappears; keep the keyboard position on its neighbour
    /// instead of snapping back to the top of the list.
    func moveSelectionOff(_ id: String) {
        guard selectedId == id else { return }
        let ids = visibleIdsInOrder
        guard let index = ids.firstIndex(of: id) else { return }
        if index + 1 < ids.count {
            selectedId = ids[index + 1]
        } else if index > 0 {
            selectedId = ids[index - 1]
        } else {
            selectedId = nil
        }
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
    private func confirmIfNeeded(title: String, message: String, owner: AgentOwner?, alwaysAsk: Bool = false) -> Bool {
        let decision = KillDecision.forHuman(target: owner)
        guard portManager.confirmBeforeKill || decision != .allow || alwaysAsk else { return true }

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
        KillConfirm.run(title: title, message: message) { dontAskAgain in
            if dontAskAgain { portManager.confirmBeforeKill = false }
        }
    }

    /// ⌘K and the footer button kill what the active filter shows, never
    /// web servers from behind the Databases tab.
    func killAllForCurrentFilter() {
        if filter == .tests {
            killAllTests()
            return
        }

        let targets = portManager.visiblePorts.filter {
            filter.includesInBulkKill($0) && !portManager.isProtectedProcessName($0.processName)
        }
        if targets.isEmpty {
            KillConfirm.inform(title: "Nothing to Kill", message: "There are no unprotected processes matching this filter.")
            return
        }

        let processList = targets.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
        let agentNote = KillDecision.liveAgentNote(for: targets.map(\.agentOwner)).map { "\n\n\($0)" } ?? ""
        let confirmed = KillConfirm.run(
            title: "\(filter.bulkKillLabel): \(targets.count) process\(targets.count == 1 ? "" : "es")?",
            message: "This will terminate the following processes:\n\n\(processList)\(agentNote)\n\nAre you sure?",
            confirmTitle: "Kill All"
        )
        if confirmed {
            portManager.killPorts(targets)
        }
    }

    func killAllTests() {
        let testProcesses = portManager.activeTests
        let killableTests = testProcesses.filter { !portManager.isProtectedProcessName($0.processName) }

        if killableTests.isEmpty {
            KillConfirm.inform(
                title: "No Test Processes Found",
                message: testProcesses.isEmpty ? "There are no active test processes to kill." : "All active test processes are protected."
            )
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
