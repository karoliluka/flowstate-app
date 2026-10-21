import Foundation
import UserNotifications

/// Local notifications for phase changes, so the user knows even when the phone is locked.
@MainActor
enum PomodoroNotifications {
    /// How many rounds ahead to schedule. Ending the session cancels the rest.
    private static let roundsAhead = 8
    /// The session the notifications are for; cleared when it ends, so a late
    /// scheduling task can't add notifications for a session that's already over.
    private static var sessionStart: Date?

    private static var identifiers: [String] {
        (0..<roundsAhead).flatMap { ["pomodoro.break.\($0)", "pomodoro.focus.\($0)"] }
    }

    /// Asked when the user picks Pomodoro mode, rather than over the session screen.
    static func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    static func schedule(_ config: PomodoroConfig, from start: Date) {
        sessionStart = start
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized, sessionStart == start else { return }
            removeAll()
            for round in 0..<roundsAhead {
                let roundStart = start.addingTimeInterval(Double(round) * config.cycle)
                add(
                    id: "pomodoro.break.\(round)",
                    at: roundStart.addingTimeInterval(config.focus),
                    title: "Break time",
                    body: "Nice work. Rest for \(config.breakMinutes) min."
                )
                add(
                    id: "pomodoro.focus.\(round)",
                    at: roundStart.addingTimeInterval(config.cycle),
                    title: "Back to focus",
                    body: "Round \(round + 2) starts now."
                )
            }
        }
    }

    static func cancel() {
        sessionStart = nil
        removeAll()
    }

    private static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func add(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
