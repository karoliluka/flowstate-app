import ActivityKit
import Foundation

/// Starts, refreshes and ends the session's Live Activity (Lock Screen and Dynamic Island).
///
/// The timer and goal bars run on their own, so the activity only needs new goals once the
/// current ones have passed. The app refreshes them whenever it comes to or leaves the foreground.
@MainActor
enum FocusLiveActivity {
    private typealias FocusActivity = Activity<FocusActivityAttributes>

    static func start(startedAt: Date, subject: Subject?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let attributes = FocusActivityAttributes(
            startedAt: startedAt,
            subjectName: subject.displayName,
            colorHex: subject?.colorHex ?? "8E8E93"
        )
        _ = try? FocusActivity.request(attributes: attributes, content: content(startedAt: startedAt))
    }

    /// Brings the activity in line with the running session: new goals, or a fresh activity if the
    /// old one was dismissed or ran out (iOS ends Live Activities after 8 hours).
    static func refresh(startedAt: Date, subject: Subject?) {
        let current = FocusActivity.activities.filter { $0.activityState == .active }
        guard let activity = current.first(where: { $0.attributes.startedAt == startedAt }) else {
            // Only possible while the app is in the foreground; iOS refuses it in the background.
            start(startedAt: startedAt, subject: subject)
            return
        }
        for other in current where other.id != activity.id {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        Task { await activity.update(content(startedAt: startedAt)) }
    }

    static func endAll() {
        for activity in FocusActivity.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func content(startedAt: Date) -> ActivityContent<FocusActivityAttributes.ContentState> {
        let elapsed = max(0, Date.now.timeIntervalSince(startedAt))
        // Seeded by the session, so the same session keeps showing the same kinds of goals.
        let goals = FocusComparisons.goals(after: elapsed, seed: UInt64(startedAt.timeIntervalSince1970)).map {
            FocusActivityAttributes.Goal(
                id: "\($0.comparison.id).\($0.count)",
                icon: $0.comparison.icon,
                title: "\($0.count)× \($0.comparison.shortName)",
                reachedAfter: $0.reachedAfter
            )
        }
        return ActivityContent(state: .init(goals: goals), staleDate: nil)
    }
}
