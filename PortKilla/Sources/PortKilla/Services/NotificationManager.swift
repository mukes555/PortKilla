import Foundation
import AppKit
import UserNotifications

// MARK: - NotificationManager
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override private init() {
        super.init()
        // Request permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
        UNUserNotificationCenter.current().delegate = self
    }

    func showSuccess(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "PortKilla"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "PortKilla Error"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showWarning(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "PortKilla Warning"
        content.body = message

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
