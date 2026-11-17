import ActivityKit
import Foundation

/// The running focus session, shown as a Live Activity on the Lock Screen and in the Dynamic Island.
///
/// Shared by the app (which starts, updates and ends it) and the widget extension (which draws it).
/// The timer and progress bars count by themselves, so nothing has to update them while the app is closed.
struct FocusActivityAttributes: ActivityAttributes {
    /// What changes during a session: the next few "that's like" goals.
    struct ContentState: Codable, Hashable {
        var goals: [Goal]
    }

    /// One comparison to reach, e.g. "2× sitcom episodes" at 44 minutes into the session.
    struct Goal: Codable, Hashable, Identifiable {
        var id: String
        /// SF Symbol name.
        var icon: String
        /// "2× sitcom episodes"
        var title: String
        /// Seconds after the session start when this goal is reached.
        var reachedAfter: TimeInterval
    }

    var startedAt: Date
    var subjectName: String
    /// "RRGGBB"
    var colorHex: String
}
