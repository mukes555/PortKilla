import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+).
public enum LoginItem {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS returns this after the app bundle was replaced (a Homebrew
    /// reinstall re-signs it) until the user re-approves it in Login Items.
    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Returns false when registration isn't possible, e.g. when running the
    /// bare SwiftPM binary during development instead of the .app bundle.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
