import Foundation

/// Every UserDefaults key the app writes, in one place, so "reset all
/// settings" and the docs can see the whole surface.
public enum DefaultsKey {
    public static let refreshIntervalSeconds = "PortKilla.refreshIntervalSeconds"
    public static let protectedProcessSubstrings = "PortKilla.protectedProcessSubstrings"
    public static let hideSystemProcesses = "PortKilla.hideSystemProcesses"
    public static let confirmBeforeKill = "PortKilla.confirmBeforeKill"
    public static let viewDensity = "PortKilla.viewDensity"
    public static let showMenuBarCount = "PortKilla.showMenuBarCount"
    public static let menuBarIcon = "PortKilla.menuBarIcon"
    public static let popoverSize = "PortKilla.popoverSize"
    public static let notificationsEnabled = "PortKilla.notificationsEnabled"
    public static let notificationSound = "PortKilla.notificationSound"
    public static let historyLimit = "PortKilla.historyLimit"
    public static let watchedPorts = "PortKilla.watchedPorts"
    public static let guardedPorts = "PortKilla.guardedPorts"
    public static let hotkeyKeyCode = "PortKilla.hotkeyKeyCode"
    public static let hotkeyModifiers = "PortKilla.hotkeyModifiers"
    public static let hotkeyDisplay = "PortKilla.hotkeyDisplay"
    public static let hasLaunchedBefore = "PortKilla.hasLaunchedBefore"
    public static let didDismissHotkeyTip = "PortKilla.didDismissHotkeyTip"
    public static let didFinishTour = "PortKilla.didFinishTour"
    public static let probeLocalServers = "PortKilla.probeLocalServers"
    public static let lastUpdateCheck = "PortKilla.lastUpdateCheck"
    /// Unprefixed for compatibility with history saved by 1.0.
    public static let history = "portHistory"
    /// Refusals live apart from kills so an older app reading `history`
    /// never meets an action it cannot decode.
    public static let refusals = "PortKilla.refusals"
    /// Port leases, shared by the CLI and the app.
    public static let reservations = "PortKilla.reservations"
}
