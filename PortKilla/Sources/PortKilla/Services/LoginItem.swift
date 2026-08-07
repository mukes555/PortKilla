import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+).
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns false when registration isn't possible — e.g. when running the
    /// bare SwiftPM binary during development instead of the .app bundle.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
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
