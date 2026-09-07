import Foundation

// MARK: - What the list shows
// System daemons, UDP sockets, and ephemeral ports are filtered here, once
// per scan; the menu bar count follows the same rules.
extension PortManager {

    private static let systemPathPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"
    ]

    private static let currentUser = NSUserName()

    /// True for ports owned by other users (root, _daemons) or by binaries
    /// living in system locations.
    public func isSystemPort(_ port: PortInfo) -> Bool {
        if port.user != Self.currentUser {
            return true
        }
        return Self.systemPathPrefixes.contains { port.command.hasPrefix($0) }
    }

    public func recomputeVisiblePorts() {
        let userPorts = activePorts.filter { !isSystemPort($0) && isShown($0) }
        visiblePorts = hideSystemProcesses ? userPorts : activePorts.filter(isShown)
        menuBarBadgeCount = userPorts.filter { $0.type != .ide }.count
    }

    /// The Display preferences: UDP sockets and ephemeral ports.
    public func isShown(_ port: PortInfo) -> Bool {
        if !showUDP && port.proto == "udp" { return false }
        if hideEphemeralPorts && port.port >= 49152 { return false }
        return true
    }

    /// How many ports the filters are swallowing right now, all of them:
    /// system processes, UDP, ephemeral.
    public var hiddenPortsCount: Int {
        activePorts.count - visiblePorts.count
    }

    /// Every filter off, for the "show hidden" hint and the empty state.
    public func showEverything() {
        hideSystemProcesses = false
        showUDP = true
        hideEphemeralPorts = false
    }
}
