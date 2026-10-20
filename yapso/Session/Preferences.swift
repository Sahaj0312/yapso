import Foundation

/// UserDefaults keys for per-device settings, used with `@AppStorage`. Not synced: a reminder time is about one phone.
nonisolated enum Preferences {
    static let hasOnboarded = "hasOnboarded"
    static let spinSound = "spinSound"
    static let reminderEnabled = "reminderEnabled"
    /// Minutes after midnight.
    static let reminderMinutes = "reminderMinutes"

    static let defaultReminderMinutes = 18 * 60

    static var reminderIsEnabled: Bool {
        UserDefaults.standard.object(forKey: reminderEnabled) as? Bool ?? true
    }

    static var reminderTime: Int {
        UserDefaults.standard.object(forKey: reminderMinutes) as? Int ?? defaultReminderMinutes
    }
}
