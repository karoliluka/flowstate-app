import Foundation
import SwiftData

/// Something the user focuses on, e.g. "Math", "Reading", "Side project".
@Model
final class Subject {
    var uuid: UUID
    var name: String
    var colorHex: String = "5C789E"
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.subject)
    var sessions: [FocusSession] = []

    init(name: String, colorHex: String, createdAt: Date = .now) {
        self.uuid = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var thisWeekDuration: TimeInterval {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start
        return sessions.filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.duration }
    }
}
