import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private(set) var authorized = false
    private let center = UNUserNotificationCenter.current()
    private let category = "GLISSE_TIMER"

    func setup() {
        center.delegate = self
        let snooze5 = UNNotificationAction(identifier: "SNOOZE_5", title: "Encore 5 min")
        let snooze15 = UNNotificationAction(identifier: "SNOOZE_15", title: "Encore 15 min")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [snooze5, snooze15], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func schedule(_ t: GTimer) {
        let content = UNMutableNotificationContent()
        content.title = t.label.isEmpty ? "C'est l'heure !" : t.label
        content.body = "Minuteur de \(Fmt.duration(Int(t.duration.rounded()))) terminé · lancé à \(Fmt.clock(t.start))"
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["label": t.label]
        let interval = max(1, t.end.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger))
    }

    func cancel(_ id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    // Afficher la bannière même si l'app est « au premier plan ».
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let label = response.notification.request.content.userInfo["label"] as? String ?? ""
        let extra: Int? = switch response.actionIdentifier {
        case "SNOOZE_5": 300
        case "SNOOZE_15": 900
        default: nil
        }
        if let extra {
            Task { @MainActor in TimerStore.shared.add(seconds: extra, label: label) }
        }
        completionHandler()
    }
}
