import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Which notifications the user wants. Stored with @AppStorage under these keys.
struct NotificationPreferences {
    static let morningNudgeKey = "notifications.morningNudge"
    /// Minutes after midnight.
    static let morningNudgeTimeKey = "notifications.morningNudgeTime"
    static let dailyReminderKey = "notifications.dailyReminder"
    /// Minutes after midnight.
    static let dailyReminderTimeKey = "notifications.dailyReminderTime"
    static let streakProtectorKey = "notifications.streakProtector"
    /// Minutes after midnight.
    static let streakProtectorTimeKey = "notifications.streakProtectorTime"
    static let weeklyRecapKey = "notifications.weeklyRecap"
    static let milestonesKey = "notifications.milestones"
    static let personalBestsKey = "notifications.personalBests"

    static let defaultMorningTime = 8 * 60
    static let defaultReminderTime = 16 * 60
    static let defaultStreakTime = 20 * 60
    /// The morning nudge goes out between 4:00 and 10:00.
    static let morningRange = (4 * 60)...(10 * 60)
    /// The daily reminder is an afternoon nudge, 12:00 to 18:00.
    static let reminderRange = (12 * 60)...(18 * 60)

    var morningNudge = true
    var morningNudgeTime = defaultMorningTime
    var dailyReminder = false
    var dailyReminderTime = defaultReminderTime
    var streakProtector = true
    var streakProtectorTime = defaultStreakTime
    var weeklyRecap = true
    var milestones = true
    var personalBests = true

    static var current: NotificationPreferences {
        let defaults = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func minutes(_ key: String, _ fallback: Int, in range: ClosedRange<Int> = 0...(24 * 60 - 1)) -> Int {
            (defaults.object(forKey: key) as? Int ?? fallback).clamped(to: range)
        }
        var preferences = NotificationPreferences()
        preferences.morningNudge = flag(morningNudgeKey, true)
        preferences.morningNudgeTime = minutes(morningNudgeTimeKey, defaultMorningTime, in: morningRange)
        preferences.dailyReminder = flag(dailyReminderKey, false)
        preferences.dailyReminderTime = minutes(dailyReminderTimeKey, defaultReminderTime, in: reminderRange)
        preferences.streakProtector = flag(streakProtectorKey, true)
        preferences.streakProtectorTime = minutes(streakProtectorTimeKey, defaultStreakTime)
        preferences.weeklyRecap = flag(weeklyRecapKey, true)
        preferences.milestones = flag(milestonesKey, true)
        preferences.personalBests = flag(personalBestsKey, true)
        return preferences
    }
}

/// Notification titles, each led by its emoji.
enum NotificationTitle {
    static let morningNudge = "☀️ Good morning"
    static let dailyReminder = "⏳ Time to focus"
    static let streakProtector = "🔥 Keep your streak"
    static let weeklyRecap = "🔁 Your week in focus"
    static let milestone = "🏆 New milestone!"
    static let personalBest = "🥇 New personal best!"
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
        func at(minutes: Int, on day: Date) -> Date {
            at(minutes / 60, minute: minutes % 60, on: day)
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
                let date = at(minutes: preferences.morningNudgeTime, on: day)
                guard date > now, let total = totals[focusDay], total > 0 else { continue }
                let top = subjectTotals[focusDay]?.max { $0.value < $1.value }?.key
                items.append(Item(
                    id: "focus.morning.\(Int(day.timeIntervalSince1970))",
                    date: date,
                    title: NotificationTitle.morningNudge,
                    body: "Yesterday you focused for \(total.focusFormatted)" + (top.map { ", mostly \($0)" } ?? "") + ". Keep it going today?"
                ))
            }
        }

        if preferences.dailyReminder {
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                let date = at(minutes: preferences.dailyReminderTime, on: day)
                guard date > now, !(offset == 0 && focusedToday) else { continue }
                items.append(Item(
                    id: "focus.reminder.\(offset)",
                    date: date,
                    title: NotificationTitle.dailyReminder,
                    body: "You haven't focused yet today. Even 25 minutes counts."
                ))
            }
        }

        if preferences.streakProtector {
            if !focusedToday {
                let current = streak(endingOn: yesterday)
                let date = at(minutes: preferences.streakProtectorTime, on: today)
                if current > 0, date > now {
                    items.append(Self.streakItem(id: "focus.streak.today", date: date, days: current))
                }
            } else {
                items.append(Self.streakItem(id: "focus.streak.tomorrow", date: at(minutes: preferences.streakProtectorTime, on: tomorrow), days: streak(endingOn: today)))
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
                items.append(Item(id: "focus.recap", date: date, title: NotificationTitle.weeklyRecap, body: body + " Tap for your recap.", weekStart: week.start))
            }
        }

        self.items = items
    }

    private static func streakItem(id: String, date: Date, days: Int) -> Item {
        Item(
            id: id,
            date: date,
            title: NotificationTitle.streakProtector,
            body: "Your \(days)-day streak ends at midnight. One session keeps it going."
        )
    }
}

/// Schedules flowstate's local notifications and sends the celebration ones.
@MainActor
enum FocusNotifications {
    private static let prefix = "focus."
    static let celebrationPrefix = "focus.celebrate."
    static let testPrefix = "focus.test."

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
            title: NotificationTitle.milestone,
            body: "You've focused for \(Int(hours).formatted()) hours in total. Keep going.",
            symbol: "trophy.fill"
        )
    }

    static func celebratePersonalBest(duration: TimeInterval) async {
        guard NotificationPreferences.current.personalBests else { return }
        await send(
            id: "best.\(Int(Date.now.timeIntervalSince1970))",
            title: NotificationTitle.personalBest,
            body: "\(duration.focusFormatted) is your longest focus session ever.",
            symbol: "medal.fill"
        )
    }

    private static func send(
        id: String,
        title: String,
        body: String,
        symbol: String? = nil,
        prefix: String = celebrationPrefix,
        delay: TimeInterval = 1,
        weekStart: Date? = nil
    ) async {
        guard await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let symbol, let attachment = goldBadge(symbol: symbol, id: id) {
            content.attachments = [attachment]
        }
        if let weekStart {
            content.userInfo = [NotificationRouter.recapWeekKey: weekStart.timeIntervalSince1970]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
    }

    #if DEBUG
    // FOR DEVELOPMENT ONLY. Debug builds only; remove before the App Store release.
    enum TestKind: String, CaseIterable, Identifiable {
        case morningNudge = "Morning nudge"
        case dailyReminder = "Daily reminder"
        case streakProtector = "Streak protector"
        case weeklyRecap = "Weekly recap"
        case milestone = "Milestone"
        case personalBest = "Personal best"

        var id: Self { self }
    }

    /// Sends a sample of a notification in 5 seconds, so it can be seen from the lock screen too.
    static func sendTest(_ kind: TestKind) async {
        let id = "\(kind.rawValue).\(Int(Date.now.timeIntervalSince1970))"
        switch kind {
        case .morningNudge:
            await send(id: id, title: NotificationTitle.morningNudge, body: "Yesterday you focused for 2h 14m, mostly Calculus. Keep it going today?", prefix: testPrefix, delay: 5)
        case .dailyReminder:
            await send(id: id, title: NotificationTitle.dailyReminder, body: "You haven't focused yet today. Even 25 minutes counts.", prefix: testPrefix, delay: 5)
        case .streakProtector:
            await send(id: id, title: NotificationTitle.streakProtector, body: "Your 6-day streak ends at midnight. One session keeps it going.", prefix: testPrefix, delay: 5)
        case .weeklyRecap:
            await send(
                id: id,
                title: NotificationTitle.weeklyRecap,
                body: "13h 3m this week, up 64% from last week. Most time on Chemistry (4h 20m). Tap for your recap.",
                prefix: testPrefix,
                delay: 5,
                weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start
            )
        case .milestone:
            await send(id: id, title: NotificationTitle.milestone, body: "You've focused for 100 hours in total. Keep going.", symbol: "trophy.fill", prefix: testPrefix, delay: 5)
        case .personalBest:
            await send(id: id, title: NotificationTitle.personalBest, body: "2h 05m is your longest focus session ever.", symbol: "medal.fill", prefix: testPrefix, delay: 5)
        }
    }
    #endif

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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
