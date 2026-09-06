import AppKit
import PortKillaCore
import SwiftUI

// MARK: - Managed runtimes
// A supervised listener gets the verb that frees the port for real instead
// of a kill that lasts a second.
extension PortListView {

    enum ManagedChoice {
        case stop
        case killAnyway
        case cancel
    }

    /// Offers the right verb for a supervised listener. Returns false when
    /// the caller should fall through to a plain kill.
    func requestManagedStop(_ port: PortInfo, managed: ManagedRuntime) -> Bool {
        switch managed.kind {
        case .reloader:
            let confirmed = runKillConfirmation(
                title: "Stop \(managed.label)?",
                message: "It supervises '\(port.processName)' (PID \(port.pid)) on :\(port.port) and \(managed.consequence). PortKilla stops the supervisor and everything under it."
            )
            guard confirmed else { return true }
            moveSelectionOff(port.id)
            portManager.stopSupervisor(of: port)
            return true
        case .pm2, .launchd, .docker:
            switch runManagedChoice(port, managed: managed) {
            case .stop:
                moveSelectionOff(port.id)
                portManager.stopManaged(port)
            case .killAnyway:
                moveSelectionOff(port.id)
                portManager.killPort(port)
            case .cancel:
                break
            }
            return true
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
