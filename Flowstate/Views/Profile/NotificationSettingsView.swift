import SwiftUI
import UserNotifications

/// Profile → Notifications: each kind on or off, with its own time where it has one.
struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(NotificationPreferences.morningNudgeKey) private var morningNudge = true
    @AppStorage(NotificationPreferences.morningNudgeTimeKey) private var morningNudgeTime = NotificationPreferences.defaultMorningTime
    @AppStorage(NotificationPreferences.dailyReminderKey) private var dailyReminder = false
    @AppStorage(NotificationPreferences.dailyReminderTimeKey) private var dailyReminderTime = NotificationPreferences.defaultReminderTime
    @AppStorage(NotificationPreferences.streakProtectorKey) private var streakProtector = true
    @AppStorage(NotificationPreferences.streakProtectorTimeKey) private var streakProtectorTime = NotificationPreferences.defaultStreakTime
    @AppStorage(NotificationPreferences.weeklyRecapKey) private var weeklyRecap = true
    @AppStorage(NotificationPreferences.milestonesKey) private var milestones = true
    @AppStorage(NotificationPreferences.personalBestsKey) private var personalBests = true

    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            permissionSection

            Group {
                Section {
                    Toggle("Morning nudge", isOn: $morningNudge)
                    if morningNudge {
                        timePicker("Time", minutes: $morningNudgeTime, in: NotificationPreferences.morningRange)
                    }
                } footer: {
                    Text("How long you focused yesterday and on what. Only after days you focused. Between 4:00 and 10:00.")
                }

                Section {
                    Toggle("Daily reminder", isOn: $dailyReminder)
                    if dailyReminder {
                        timePicker("Time", minutes: $dailyReminderTime, in: NotificationPreferences.reminderRange)
                    }
                } footer: {
                    Text("An afternoon nudge, only if you haven't logged a focus session yet that day. Between 12:00 and 18:00.")
                }

                Section {
                    Toggle("Streak protector", isOn: $streakProtector)
                    if streakProtector {
                        timePicker("Time", minutes: $streakProtectorTime)
                    }
                } footer: {
                    Text("A heads-up when your streak would end at midnight because you haven't focused yet.")
                }

                Section {
                    Toggle("Weekly recap", isOn: $weeklyRecap)
                } footer: {
                    Text("Your week in focus, on the last day of the week at 18:00. Tap it for the full recap.")
                }

                Section {
                    Toggle(isOn: $milestones) {
                        Label("Milestones", systemImage: "trophy.fill")
                    }
                    Toggle(isOn: $personalBests) {
                        Label("Personal bests", systemImage: "medal.fill")
                    }
                } header: {
                    Text("Celebrations")
                } footer: {
                    Text("When you pass an hour milestone or finish your longest session yet.")
                }
            }
            .disabled(status == .denied)

            #if DEBUG
            // FOR DEVELOPMENT ONLY: remove this section before the App Store release.
            Section {
                ForEach(FocusNotifications.TestKind.allCases) { kind in
                    Button("Send \(kind.rawValue.lowercased())") {
                        Task { await FocusNotifications.sendTest(kind) }
                    }
                }
            } header: {
                Text("Test (development only)")
            } footer: {
                Text("Each sample arrives in 5 seconds, so you can lock the phone or leave the app to see it like a user would. Debug builds only. Remove before release.")
            }
            #endif
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: [morningNudge, dailyReminder, streakProtector])
        .task { status = await FocusNotifications.authorizationStatus() }
        .onChange(of: [morningNudge, dailyReminder, streakProtector, weeklyRecap, milestones, personalBests]) { _, _ in
            Task { await settingsChanged() }
        }
        .onChange(of: [morningNudgeTime, dailyReminderTime, streakProtectorTime]) { _, _ in
            Task { await settingsChanged() }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch status {
        case .denied:
            Section {
                Text("Notifications are off for flowstate in your iPhone's Settings.")
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .notDetermined:
            Section {
                Button("Turn on notifications") {
                    Task { await askPermission() }
                }
            }
        default:
            EmptyView()
        }
    }

    /// A time of day stored as minutes after midnight, optionally limited to a window.
    private func timePicker(_ title: String, minutes: Binding<Int>, in range: ClosedRange<Int> = 0...(24 * 60 - 1)) -> some View {
        let calendar = Calendar.current
        func date(_ minutes: Int) -> Date {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
        let selection = Binding<Date>(
            get: { date(minutes.wrappedValue.clamped(to: range)) },
            set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)).clamped(to: range)
            }
        )
        return DatePicker(title, selection: selection, in: date(range.lowerBound)...date(range.upperBound), displayedComponents: .hourAndMinute)
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
