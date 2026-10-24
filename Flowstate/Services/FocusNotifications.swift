import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Which notifications the user wants. Stored with @AppStorage under these keys.
struct NotificationPreferences {
    static let morningNudgeKey = "notifications.morningNudge"
    static let dailyReminderKey = "notifications.dailyReminder"
    /// Minutes after midnight.
    static let dailyReminderTimeKey = "notifications.dailyReminderTime"
    static let streakProtectorKey = "notifications.streakProtector"
    static let weeklyRecapKey = "notifications.weeklyRecap"
    static let milestonesKey = "notifications.milestones"
    static let personalBestsKey = "notifications.personalBests"

    static let defaultReminderTime = 16 * 60

    var morningNudge = true
    var dailyReminder = false
    var dailyReminderTime = defaultReminderTime
    var streakProtector = true
    var weeklyRecap = true
    var milestones = true
    var personalBests = true

    static var current: NotificationPreferences {
        let defaults = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        var preferences = NotificationPreferences()
        preferences.morningNudge = flag(morningNudgeKey, true)
        preferences.dailyReminder = flag(dailyReminderKey, false)
        preferences.dailyReminderTime = defaults.object(forKey: dailyReminderTimeKey) as? Int ?? defaultReminderTime
        preferences.streakProtector = flag(streakProtectorKey, true)
        preferences.weeklyRecap = flag(weeklyRecapKey, true)
        preferences.milestones = flag(milestonesKey, true)
        preferences.personalBests = flag(personalBestsKey, true)
        return preferences
    }
}

/// The scheduled notifications, worked out from the sessions so far. Pure, so it can be tested.
///
/// Sessions only ever happen inside the app, and everything is rescheduled after each one,
/// so a notification's content is always up to date when it's delivered.
struct NotificationPlan {
    struct Record {
        let start: Date
        let duration: TimeInterval
        let subject: String?
    }

    struct Item: Equatable {
        let id: String
        let date: Date
        let title: String
        let body: String
        var weekStart: Date?
    }

    static let morningHour = 8
    static let streakHour = 20
    static let recapHour = 18

    let items: [Item]

    init(records: [Record], preferences: NotificationPreferences, now: Date, calendar: Calendar = .current) {
        var totals: [Date: TimeInterval] = [:]
        var subjectTotals: [Date: [String: TimeInterval]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.start)
            totals[day, default: 0] += record.duration
            if let subject = record.subject {
                subjectTotals[day, default: [:]][subject, default: 0] += record.duration
            }
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let focusedToday = (totals[today] ?? 0) > 0
        func at(_ hour: Int, minute: Int = 0, on day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func streak(endingOn day: Date) -> Int {
            var count = 0
            var day = day
            while (totals[day] ?? 0) > 0 {
                count += 1
                day = calendar.date(byAdding: .day, value: -1, to: day)!
            }
            return count
        }
        var items: [Item] = []

        if preferences.morningNudge {
            // Tomorrow morning looks back on today; early today, it looks back on yesterday.
            for (day, focusDay) in [(today, yesterday), (tomorrow, today)] {
                let date = at(Self.morningHour, on: day)
                guard date > now, let total = totals[focusDay], total > 0 else { continue }
                let top = subjectTotals[focusDay]?.max { $0.value < $1.value }?.key
                items.append(Item(
                    id: "focus.morning.\(Int(day.timeIntervalSince1970))",
                    date: date,
                    title: "Good morning",
                    body: "Yesterday you focused for \(total.focusFormatted)" + (top.map { ", mostly \($0)" } ?? "") + ". Keep it going today?"
                ))
            }
        }

        if preferences.dailyReminder {
            let hour = preferences.dailyReminderTime / 60
            let minute = preferences.dailyReminderTime % 60
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                let date = at(hour, minute: minute, on: day)
                guard date > now, !(offset == 0 && focusedToday) else { continue }
                items.append(Item(
                    id: "focus.reminder.\(offset)",
                    date: date,
                    title: "Time to focus",
                    body: "You haven't focused yet today. Even 25 minutes counts."
                ))
            }
        }

        if preferences.streakProtector {
            if !focusedToday {
                let current = streak(endingOn: yesterday)
                let date = at(Self.streakHour, on: today)
                if current > 0, date > now {
                    items.append(Self.streakItem(id: "focus.streak.today", date: date, days: current))
                }
            } else {
                items.append(Self.streakItem(id: "focus.streak.tomorrow", date: at(Self.streakHour, on: tomorrow), days: streak(endingOn: today)))
            }
        }

        if preferences.weeklyRecap, let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            let lastDay = calendar.date(byAdding: .day, value: -1, to: week.end)!
            let date = at(Self.recapHour, on: lastDay)
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start)!
            let thisWeek = records.filter { $0.start >= week.start && $0.start < week.end }
            let total = thisWeek.reduce(0) { $0 + $1.duration }
            if date > now, total > 0 {
                let lastWeek = records.filter { $0.start >= lastWeekStart && $0.start < week.start }.reduce(0) { $0 + $1.duration }
                var bySubject: [String: TimeInterval] = [:]
                for record in thisWeek { if let subject = record.subject { bySubject[subject, default: 0] += record.duration } }
                var body = "\(total.focusFormatted) this week"
                if lastWeek > 0 {
                    let change = Int(((total - lastWeek) / lastWeek * 100).rounded())
                    body += change == 0 ? ", same as last week" : ", \(change > 0 ? "up" : "down") \(abs(change))% from last week"
                }
                body += "."
                if let top = bySubject.max(by: { $0.value < $1.value }) {
                    body += " Most time on \(top.key) (\(top.value.focusFormatted))."
                }
                items.append(Item(id: "focus.recap", date: date, title: "Your week in focus", body: body + " Tap for your recap.", weekStart: week.start))
            }
        }

        self.items = items
    }

    private static func streakItem(id: String, date: Date, days: Int) -> Item {
        Item(
            id: id,
            date: date,
            title: "Keep your streak",
            body: "Your \(days)-day streak ends at midnight. One session keeps it going."
        )
    }
}

/// Schedules flowstate's local notifications and sends the celebration ones.
@MainActor
enum FocusNotifications {
    private static let prefix = "focus."
    static let celebrationPrefix = "focus.celebrate."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every scheduled notification with a fresh plan. Call when the app opens,
    /// after a session ends, and when notification settings change.
    static func reschedule(context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled)
        guard await authorizationStatus() == .authorized else { return }

        let since = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since })
        let records = ((try? context.fetch(descriptor)) ?? []).map {
            NotificationPlan.Record(start: $0.startedAt, duration: $0.duration, subject: $0.subject?.name)
        }
        for item in NotificationPlan(records: records, preferences: .current, now: now).items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            if let weekStart = item.weekStart {
                content.userInfo = [NotificationRouter.recapWeekKey: weekStart.timeIntervalSince1970]
            }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    static func celebrateMilestone(hours: Double) async {
        guard NotificationPreferences.current.milestones else { return }
        await send(
            id: "milestone.\(Int(hours))",
            title: "Milestone reached",
            body: "You've focused for \(Int(hours).formatted()) hours in total. Keep going.",
            symbol: "trophy.fill"
        )
    }

    static func celebratePersonalBest(duration: TimeInterval) async {
        guard NotificationPreferences.current.personalBests else { return }
        await send(
            id: "best.\(Int(Date.now.timeIntervalSince1970))",
            title: "New personal best",
            body: "\(duration.focusFormatted) is your longest focus session ever.",
            symbol: "medal.fill"
        )
    }

    private static func send(id: String, title: String, body: String, symbol: String) async {
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let attachment = goldBadge(symbol: symbol, id: id) {
            content.attachments = [attachment]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: celebrationPrefix + id, content: content, trigger: trigger))
    }

    /// A gold symbol on the app's dark background, shown as the notification's thumbnail.
    private static func goldBadge(symbol: String, id: String) -> UNNotificationAttachment? {
        let size = CGSize(width: 300, height: 300)
        let configuration = UIImage.SymbolConfiguration(pointSize: 150, weight: .regular)
        guard let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
            .withTintColor(UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 1), renderingMode: .alwaysOriginal) else { return nil }
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 8 / 255, green: 8 / 255, blue: 8 / 255, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            glyph.draw(in: CGRect(
                x: (size.width - glyph.size.width) / 2,
                y: (size.height - glyph.size.height) / 2,
                width: glyph.size.width,
                height: glyph.size.height
            ))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).png")
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id, url: url)
    }
}

/// Receives notification taps and decides how notifications show while the app is open.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let recapWeekKey = "recapWeek"

    struct RecapWeek: Identifiable {
        let start: Date
        var id: Date { start }
    }

    /// The week whose recap is open.
    var recap: RecapWeek?

    func showRecap(for date: Date) {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else { return }
        recap = RecapWeek(start: week.start)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Celebrations already show on the session summary; just keep them in Notification Center.
        notification.request.identifier.hasPrefix(FocusNotifications.celebrationPrefix) ? [.list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let start = response.notification.request.content.userInfo[Self.recapWeekKey] as? TimeInterval else { return }
        await MainActor.run { recap = RecapWeek(start: Date(timeIntervalSince1970: start)) }
    }
}
