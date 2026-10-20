import AVFoundation
import UserNotifications

nonisolated enum Permissions {
    static var microphoneGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Asked once, at the first spin, so the "time's up" nudge works while the user researches elsewhere.
    static func requestNotificationsIfUndetermined() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
