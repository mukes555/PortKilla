import Foundation
import AppKit
import UserNotifications

// MARK: - NotificationManager
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override private init() {
        super.init()
        // We defer requesting permissions until needed, or check if we have a bundle ID.
        // Running via 'swift run' often lacks a proper bundle ID, causing UNUserNotificationCenter to crash.
        
        if Bundle.main.bundleIdentifier != nil {
            setupNotifications()
        }
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
        UNUserNotificationCenter.current().delegate = self
    }

    func showSuccess(_ message: String) {
        // Fallback to NSAlert or print if no bundle ID (e.g. CLI run)
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Success] \(message)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "PortKilla"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showError(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Error] \(message)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "PortKilla Error"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showWarning(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Warning] \(message)")
            return
        }
        
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
