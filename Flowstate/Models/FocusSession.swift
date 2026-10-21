import Foundation
import SwiftData

/// A completed focus session.
@Model
final class FocusSession {
    var startedAt: Date
    var endedAt: Date
    var subject: Subject?

    init(startedAt: Date, endedAt: Date, subject: Subject?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.subject = subject
    }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
