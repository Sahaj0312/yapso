import Foundation
import UserNotifications

/// "Your topic is waiting" at the user's reminder time, only on days they haven't spun yet.
///
/// A repeating notification can't skip done days, so this schedules one-off reminders for the next week and
/// is refreshed whenever the app is opened or today's spin happens. Never prompts for permission.
nonisolated enum DailyReminder {
    private static let prefix = "daily-reminder-"
    private static let daysAhead = 7

    static func refresh(todayStarted: Bool, now: Date = .now, calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard Preferences.reminderIsEnabled,
              await center.notificationSettings().authorizationStatus == .authorized else { return }

        let minutes = Preferences.reminderTime
        for offset in 0..<daysAhead {
            if offset == 0 && todayStarted { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireAt = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fireAt > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Your topic is waiting"
            content.body = "Ten minutes to learn it, ninety seconds to explain it."
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + DayKey(fireAt, calendar: calendar).rawValue,
                                                       content: content, trigger: trigger))
        }
    }
}
