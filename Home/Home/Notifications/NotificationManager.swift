import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func personArrived(name: String, emoji: String) {
        send(id: "arrived-\(name)",
             title: "\(emoji) \(name) is home",
             body: "Just arrived on the network.")
    }

    func personLeft(name: String, emoji: String) {
        send(id: "left-\(name)",
             title: "\(emoji) \(name) left home",
             body: "No longer detected on the network.")
    }

    private func send(id: String, title: String, body: String) {
        let content      = UNMutableNotificationContent()
        content.title    = title
        content.body     = body
        content.sound    = .default
        let trigger      = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request      = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
