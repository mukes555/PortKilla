import Foundation
import UserNotifications

/// System notifications (used by the port watchlist).
///
/// UNUserNotificationCenter crashes when there is no app bundle (e.g. running
/// the bare SwiftPM binary during development), so every call is guarded.
enum Notifier {

    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
