import AppKit
import PortKillaCore
import UserNotifications

/// Turns a refusal the CLI just issued into a notification the person can
/// act on: stop the server themselves, or open PortKilla and look.
final class RefusalWatcher: NSObject, UNUserNotificationCenterDelegate {
    private let portManager: PortManager
    private let reveal: () -> Void

    init(portManager: PortManager, reveal: @escaping () -> Void) {
        self.portManager = portManager
        self.reveal = reveal
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(refused(_:)), name: RefusalSignal.name, object: nil)
        guard Notifier.isAvailable else { return }
        Notifier.registerCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func refused(_ notification: Notification) {
        guard let payload = RefusalSignal.Payload(userInfo: notification.userInfo) else { return }
        // The History window may be open; the CLI wrote to the shared store.
        HistoryManager.shared.reload()
        guard portManager.notificationsEnabled else { return }
        Notifier.sendRefusal(payload, sound: portManager.notificationSound)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let payload = RefusalSignal.Payload(userInfo: response.notification.request.content.userInfo) else { return }
        switch response.actionIdentifier {
        case Notifier.stopAnywayAction:
            // The person chose; a fresh scan finds the current occupant.
            portManager.killPortNumber(payload.port, initiator: .user)
        default:
            reveal()
        }
    }
}
