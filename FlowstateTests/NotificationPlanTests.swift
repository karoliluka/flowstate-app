import Foundation
import Testing
@testable import Flowstate

/// Which notifications get scheduled, and what they say, for a given history.
struct NotificationPlanTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    /// Wednesday 21 Oct 2026, 12:00.
    private var now: Date { date(day: 21, hour: 12) }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func session(day: Int, hour: Int, minutes: Double, _ subject: String? = "Calculus") -> NotificationPlan.Record {
        .init(start: date(day: day, hour: hour), duration: minutes * 60, subject: subject)
    }

    private func plan(_ records: [NotificationPlan.Record], _ preferences: NotificationPreferences = .init()) -> [NotificationPlan.Item] {
        NotificationPlan(records: records, preferences: preferences, now: now, calendar: calendar).items
    }

    @Test func morningNudgeLooksBackOnToday() throws {
        let items = plan([session(day: 21, hour: 9, minutes: 90), session(day: 21, hour: 11, minutes: 30, "Biology")])
        let nudge = try #require(items.first { $0.id.hasPrefix("focus.morning") })
        #expect(nudge.date == date(day: 22, hour: 8))
        #expect(nudge.body == "Yesterday you focused for 2h, mostly Calculus. Keep it going today?")
    }

    @Test func noMorningNudgeAfterADayOff() {
        #expect(!plan([session(day: 20, hour: 9, minutes: 60)]).contains { $0.id.hasPrefix("focus.morning") })
    }

    @Test func dailyReminderSkipsDaysAlreadyFocused() {
        var preferences = NotificationPreferences()
        preferences.dailyReminder = true
        preferences.dailyReminderTime = 16 * 60

        let reminders = plan([session(day: 21, hour: 9, minutes: 30)], preferences).filter { $0.id.hasPrefix("focus.reminder") }
        #expect(reminders.count == 6)
        #expect(reminders.first?.date == date(day: 22, hour: 16))

        let unfocused = plan([], preferences).filter { $0.id.hasPrefix("focus.reminder") }
        #expect(unfocused.first?.date == date(day: 21, hour: 16))
    }

    @Test func dailyReminderIsOffByDefault() {
        #expect(!plan([]).contains { $0.id.hasPrefix("focus.reminder") })
    }

    @Test func streakProtectorWarnsTonightBeforeTheStreakEnds() throws {
        let records = (18...20).map { session(day: $0, hour: 10, minutes: 45) }
        let warning = try #require(plan(records).first { $0.id == "focus.streak.today" })
        #expect(warning.date == date(day: 21, hour: 20))
        #expect(warning.body.contains("3-day streak"))
    }

    @Test func afterFocusingTodayTheStreakIsGuardedTomorrow() throws {
        let records = (20...21).map { session(day: $0, hour: 10, minutes: 45) }
        let items = plan(records)
        #expect(!items.contains { $0.id == "focus.streak.today" })
        let tomorrow = try #require(items.first { $0.id == "focus.streak.tomorrow" })
        #expect(tomorrow.date == date(day: 22, hour: 20))
        #expect(tomorrow.body.contains("2-day streak"))
    }

    @Test func weeklyRecapComparesWithLastWeek() throws {
        let records = [
            session(day: 13, hour: 10, minutes: 120),            // last week
            session(day: 19, hour: 10, minutes: 120),            // this week (Mon 19 Oct)
            session(day: 20, hour: 10, minutes: 60, "Biology"),
        ]
        let recap = try #require(plan(records).first { $0.id == "focus.recap" })
        #expect(recap.date == date(day: 25, hour: 18)) // Sunday
        #expect(recap.weekStart == date(day: 19, hour: 0))
        #expect(recap.body == "3h this week, up 50% from last week. Most time on Calculus (2h). Tap for your recap.")
    }

    @Test func noRecapForAnEmptyWeek() {
        #expect(!plan([session(day: 13, hour: 10, minutes: 60)]).contains { $0.id == "focus.recap" })
    }

    @Test func switchedOffNotificationsAreNotScheduled() {
        var preferences = NotificationPreferences()
        preferences.morningNudge = false
        preferences.streakProtector = false
        preferences.weeklyRecap = false
        #expect(plan([session(day: 21, hour: 9, minutes: 60)], preferences).isEmpty)
    }

    @Test func chosenTimesAreUsed() throws {
        var preferences = NotificationPreferences()
        preferences.morningNudgeTime = 6 * 60 + 30
        preferences.streakProtectorTime = 22 * 60 + 15
        let items = plan([session(day: 21, hour: 9, minutes: 60)], preferences)
        #expect(try #require(items.first { $0.id.hasPrefix("focus.morning") }).date == date(day: 22, hour: 6, minute: 30))
        #expect(try #require(items.first { $0.id == "focus.streak.tomorrow" }).date == date(day: 22, hour: 22, minute: 15))
    }

    @Test func storedTimesOutsideTheirWindowAreClamped() {
        #expect((2 * 60).clamped(to: NotificationPreferences.morningRange) == 4 * 60)
        #expect((20 * 60).clamped(to: NotificationPreferences.reminderRange) == 18 * 60)
        #expect((14 * 60).clamped(to: NotificationPreferences.reminderRange) == 14 * 60)
    }

    @Test func comparisonsAreRandomButRepeatablePerSeed() {
        let total: TimeInterval = 12 * 3600
        let first = FocusComparisons.matches(for: total, seed: 42).map(\.comparison.id)
        #expect(first.count == 3)
        #expect(first == FocusComparisons.matches(for: total, seed: 42).map(\.comparison.id))
        #expect(FocusComparisons.matches(for: total, seed: 42).allSatisfy { $0.count >= 1 })

        let seeds: [UInt64] = (1...20).map { $0 }
        let picks = Set(seeds.map { FocusComparisons.matches(for: total, seed: $0).map(\.comparison.id) })
        #expect(picks.count > 1)
    }
}
