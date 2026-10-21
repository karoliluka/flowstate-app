import Foundation
import SwiftData

/// Something the user focuses on, e.g. "Math", "Reading", "Side project".
@Model
final class Subject {
    var uuid: UUID
    var name: String
    var colorHex: String = "5C789E"
    /// 0 means no goal.
    var weeklyGoalMinutes: Int = 0
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.subject)
    var sessions: [FocusSession] = []

    init(name: String, colorHex: String, weeklyGoalMinutes: Int = 0, createdAt: Date = .now) {
        self.uuid = UUID()
        self.name = name
        self.colorHex = colorHex
        self.weeklyGoalMinutes = weeklyGoalMinutes
        self.createdAt = createdAt
    }

    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var thisWeekDuration: TimeInterval {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start
        return sessions.filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.duration }
    }

    var weeklyGoal: TimeInterval? {
        weeklyGoalMinutes > 0 ? Double(weeklyGoalMinutes) * 60 : nil
    }

    /// 0...1 progress toward this week's goal, nil without a goal.
    var weeklyProgress: Double? {
        weeklyGoal.map { min(1, thisWeekDuration / $0) }
    }
}
