import Foundation
import UserNotifications

/// System notifications (used by the port watchlist).
///
/// UNUserNotificationCenter crashes when there is no app bundle (e.g. running
/// the bare SwiftPM binary during development), so every call is guarded.
public enum Notifier {

    public static var isAvailable: Bool {
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

    public static let refusalCategory = "PORTKILLA_REFUSAL"
    public static let stopAnywayAction = "PORTKILLA_STOP_ANYWAY"
    public static let showAction = "PORTKILLA_SHOW"

    /// Registers the refusal category so its buttons appear; call once at launch.
    public static func registerCategories() {
        guard isAvailable else { return }
        let stop = UNNotificationAction(identifier: stopAnywayAction, title: "Stop it anyway", options: [.destructive])
        let show = UNNotificationAction(identifier: showAction, title: "Show in PortKilla", options: [.foreground])
        let category = UNNotificationCategory(identifier: refusalCategory, actions: [stop, show], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// "Claude Code was refused :3000" with the buttons a person needs to
    /// settle it; `port` rides along for the action handler.
    public static func sendRefusal(_ payload: RefusalSignal.Payload, sound: Bool = true) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(payload.caller.components(separatedBy: " via ").first ?? payload.caller) was refused :\(payload.port)"
        let owner = payload.owner.map { " owned by \($0)" } ?? " that nobody claims"
        content.body = "It asked to stop \(payload.processName)\(owner). Stop it yourself, or leave it running."
        content.sound = sound ? .default : nil
        content.categoryIdentifier = refusalCategory
        content.userInfo = payload.userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "refusal-\(payload.port)", content: content, trigger: nil))
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
