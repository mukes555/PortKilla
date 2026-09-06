import Foundation

/// Every UserDefaults key the app writes, in one place, so "reset all
/// settings" and the docs can see the whole surface.
enum DefaultsKey {
    static let refreshIntervalSeconds = "PortKilla.refreshIntervalSeconds"
    static let protectedProcessSubstrings = "PortKilla.protectedProcessSubstrings"
    static let hideSystemProcesses = "PortKilla.hideSystemProcesses"
    static let confirmBeforeKill = "PortKilla.confirmBeforeKill"
    static let viewDensity = "PortKilla.viewDensity"
    static let showMenuBarCount = "PortKilla.showMenuBarCount"
    static let notificationsEnabled = "PortKilla.notificationsEnabled"
    static let notificationSound = "PortKilla.notificationSound"
    static let historyLimit = "PortKilla.historyLimit"
    static let watchedPorts = "PortKilla.watchedPorts"
    static let guardedPorts = "PortKilla.guardedPorts"
    static let hotkeyKeyCode = "PortKilla.hotkeyKeyCode"
    static let hotkeyModifiers = "PortKilla.hotkeyModifiers"
    static let hotkeyDisplay = "PortKilla.hotkeyDisplay"
    static let hasLaunchedBefore = "PortKilla.hasLaunchedBefore"
    static let didDismissHotkeyTip = "PortKilla.didDismissHotkeyTip"
    static let lastUpdateCheck = "PortKilla.lastUpdateCheck"
    /// Unprefixed for compatibility with history saved by 1.0.
    static let history = "portHistory"
}
