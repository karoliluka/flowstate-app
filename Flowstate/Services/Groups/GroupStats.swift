import Foundation
import SwiftData

/// The focus numbers a person shares with their groups, worked out from the sessions on the phone.
enum GroupStats {
    /// Groups compare Monday-to-Sunday weeks, whatever each phone's own first weekday is.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    static func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// "2026-11-16"
    static func weekStartString(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: weekStart(for: date))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    struct Totals: Equatable {
        var total: TimeInterval
        var thisWeek: TimeInterval
        var weekStart: String
    }

    static func totals(of sessions: [(start: Date, duration: TimeInterval)], now: Date = .now) -> Totals {
        let monday = weekStart(for: now)
        return Totals(
            total: sessions.reduce(0) { $0 + $1.duration },
            thisWeek: sessions.filter { $0.start >= monday }.reduce(0) { $0 + $1.duration },
            weekStart: weekStartString(for: now)
        )
    }

    @MainActor
    static func totals(in context: ModelContext, now: Date = .now) -> Totals {
        let sessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        return totals(of: sessions.map { ($0.startedAt, $0.duration) }, now: now)
    }
}
