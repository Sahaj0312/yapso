import SwiftData
import SwiftUI
import UserNotifications

/// Reminder time, spin sound and subscription. Opened from the gear on Today.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var attempts: [Attempt]
    @AppStorage(Preferences.reminderEnabled) private var reminderEnabled = true
    @AppStorage(Preferences.reminderMinutes) private var reminderMinutes = Preferences.defaultReminderMinutes
    @AppStorage(Preferences.spinSound) private var spinSound = false
    @AppStorage(Preferences.hasOnboarded) private var hasOnboarded = true
    @State private var showPaywall = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if notificationsDenied && reminderEnabled {
                        Text("Notifications are off for Yapso. Turn them on in the Settings app to get reminders.")
                    } else {
                        Text("Only on days you haven't spun yet.")
                    }
                }

                Section {
                    Toggle("Spin sound", isOn: $spinSound)
                } footer: {
                    Text("A soft tick as the topics roll past. Follows your silent switch.")
                }

                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        LabeledContent("Yapso Pro") {
                            Text(AppConfig.hasPro ? "Active" : "Upgrade")
                        }
                    }
                    .foregroundStyle(.primary)
                }

                #if DEBUG
                Section("Debug") {
                    Button("Replay onboarding") {
                        hasOnboarded = false
                        dismiss()
                    }
                }
                #endif

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .tint(.primary)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
            .task { await checkNotifications() }
            .onChange(of: reminderEnabled) { Task { await reschedule() } }
            .onChange(of: reminderMinutes) { Task { await reschedule() } }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
        }
    }

    private func checkNotifications() async {
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private func reschedule() async {
        // Turning the reminder on is the natural moment to ask, if they never have been.
        if reminderEnabled { await Permissions.requestNotificationsIfUndetermined() }
        await checkNotifications()
        await DailyReminder.refresh(todayStarted: Attempt.dailyStarted(on: DayKey(.now), in: attempts))
    }
}
