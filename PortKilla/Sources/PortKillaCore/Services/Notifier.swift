import Foundation
import UserNotifications

/// System notifications (used by the port watchlist).
///
/// UNUserNotificationCenter crashes when there is no app bundle (e.g. running
/// the bare SwiftPM binary during development), so every call is guarded.
public enum Notifier {

    private static var isAvailable: Bool {
        // A bundle identifier alone is not enough: the xctest runner has one
        // yet UNUserNotificationCenter still throws ("bundleProxyForCurrentProcess
        // is nil"). Only a real .app bundle can use notifications.
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// nil when notifications are unavailable in this build (no .app bundle).
    public static func authorizationStatus(completion: @escaping (UNAuthorizationStatus?) -> Void) {
        guard isAvailable else {
            completion(nil)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    public static func send(title: String, body: String, sound: Bool = true) {
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
