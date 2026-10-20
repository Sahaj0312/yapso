import Foundation
import UserNotifications

/// The "1 minute left" and "time's up" nudges while the user researches outside the app.
/// Only scheduled if notification permission was already granted; never prompts.
nonisolated enum ResearchNotifications {
    static func schedule(attemptID: UUID, topicTitle: String, deadline: Date) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let nudges: [(suffix: String, fireAt: Date, title: String, body: String)] = [
            ("1min", deadline.addingTimeInterval(-60), "1 minute left", "Wrap up your research on \(topicTitle)."),
            ("up", deadline, "Time's up", "Open Yapso to speak. Your 90 seconds start when you return."),
        ]
        for nudge in nudges where nudge.fireAt > .now {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: nudge.fireAt.timeIntervalSinceNow, repeats: false)
            let request = UNNotificationRequest(identifier: "\(attemptID)-\(nudge.suffix)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func cancel(attemptID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(attemptID)-1min", "\(attemptID)-up"])
    }
}
