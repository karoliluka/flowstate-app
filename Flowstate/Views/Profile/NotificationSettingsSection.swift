import SwiftUI
import UserNotifications

/// On/off switches for each kind of notification, plus the daily reminder time.
struct NotificationSettingsSection: View {
    @Environment(\.modelContext) private var context

    @AppStorage(NotificationPreferences.morningNudgeKey) private var morningNudge = true
    @AppStorage(NotificationPreferences.dailyReminderKey) private var dailyReminder = false
    @AppStorage(NotificationPreferences.dailyReminderTimeKey) private var dailyReminderTime = NotificationPreferences.defaultReminderTime
    @AppStorage(NotificationPreferences.streakProtectorKey) private var streakProtector = true
    @AppStorage(NotificationPreferences.weeklyRecapKey) private var weeklyRecap = true
    @AppStorage(NotificationPreferences.milestonesKey) private var milestones = true
    @AppStorage(NotificationPreferences.personalBestsKey) private var personalBests = true

    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Section {
            switch status {
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for flowstate in your iPhone's Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            case .notDetermined:
                Button("Turn on notifications") {
                    Task { await askPermission() }
                }
            default:
                EmptyView()
            }

            toggle("Morning nudge", detail: "8:00, after days you focused", isOn: $morningNudge)
            toggle("Daily reminder", detail: "If you haven't focused yet that day", isOn: $dailyReminder)
            if dailyReminder {
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
            toggle("Streak protector", detail: "20:00, if your streak is about to end", isOn: $streakProtector)
            toggle("Weekly recap", detail: "Last day of the week, 18:00", isOn: $weeklyRecap)
            toggle("Milestones", detail: "When you pass an hour milestone", isOn: $milestones)
            toggle("Personal bests", detail: "After your longest session yet", isOn: $personalBests)
        } header: {
            Text("Notifications")
        }
        .task { status = await FocusNotifications.authorizationStatus() }
        .onChange(of: [morningNudge, dailyReminder, streakProtector, weeklyRecap, milestones, personalBests]) { _, _ in
            Task { await settingsChanged() }
        }
        .onChange(of: dailyReminderTime) { _, _ in
            Task { await settingsChanged() }
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(status == .denied)
    }

    /// The reminder time as a Date for the picker, stored as minutes after midnight.
    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: dailyReminderTime / 60, minute: dailyReminderTime % 60, second: 0, of: .now) ?? .now },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                dailyReminderTime = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func settingsChanged() async {
        // Switching one on is the moment to ask, rather than when the app first opens.
        if status == .notDetermined {
            await askPermission()
        } else {
            await FocusNotifications.reschedule(context: context)
        }
    }

    private func askPermission() async {
        await FocusNotifications.requestPermission()
        status = await FocusNotifications.authorizationStatus()
        await FocusNotifications.reschedule(context: context)
    }
}
