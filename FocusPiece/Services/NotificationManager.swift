import Foundation
import UserNotifications

/// Local notifications: a single phase-end reminder (round done, break over,
/// session complete) that fires when the timer runs out while the iPhone is
/// locked or the app is in background.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private static let sessionEndID = "fp.sessionEnd"
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Ask for permission the first time it is needed (e.g. when a session
    /// starts or the settings toggle is switched on). No-op once determined.
    func requestPermissionIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedule the phase-end notification `seconds` from now with the given
    /// copy. Replaces any previously scheduled one (same identifier). On first
    /// use the request is only added once authorization was actually granted —
    /// adding while "not determined" would be silently dropped.
    func scheduleSessionEnd(after seconds: Int, title: String, body: String) {
        guard seconds > 0 else { return }
        let fireDate = Date().addingTimeInterval(TimeInterval(seconds))

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { self.addSessionEndRequest(at: fireDate, title: title, body: body) }
                }
            case .denied:
                break
            default:
                self.addSessionEndRequest(at: fireDate, title: title, body: body)
            }
        }
    }

    private func addSessionEndRequest(at fireDate: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Keep the wall-clock fire moment even if authorization took a beat.
        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.sessionEndID, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelSessionEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.sessionEndID])
    }

    // MARK: UNUserNotificationCenterDelegate
    /// Suppress the banner while the app is frontmost — the completion screen
    /// itself is the celebration.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
