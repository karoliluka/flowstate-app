import Foundation
import SwiftData

/// What a session added up to, shown right after it ends.
struct SessionSummary {
    let duration: TimeInterval
    let subject: Subject?
    /// False for sessions too short to count.
    let saved: Bool
    let earnedMinutes: Double
    let balanceFull: Bool
    let focusedToday: TimeInterval

    var deepFocus: Bool { duration >= EarnedTimeManager.deepFocusThreshold }
}

/// Owns the currently running focus session.
///
/// The running session is kept in UserDefaults so it survives the app being
/// closed or killed. Shields stay on in the meantime because ManagedSettings
/// persists them at the system level.
@MainActor
@Observable
final class SessionManager {
    /// Sessions shorter than this are treated as accidental and discarded.
    static let minimumDuration: TimeInterval = 10

    private(set) var startedAt: Date?
    private(set) var subjectID: UUID?
    /// Set when a session ends, until the user closes the summary.
    private(set) var summary: SessionSummary?

    private let blocking: BlockingManager
    private let earned: EarnedTimeManager
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let startedAt = "activeSession.startedAt"
        static let subjectID = "activeSession.subjectID"
    }

    init(blocking: BlockingManager, earned: EarnedTimeManager) {
        self.blocking = blocking
        self.earned = earned
        startedAt = defaults.object(forKey: Keys.startedAt) as? Date
        subjectID = defaults.string(forKey: Keys.subjectID).flatMap(UUID.init)

        // Never leave apps blocked without a session the user can end.
        if !isActive { blocking.stopBlocking() }
    }

    var isActive: Bool { startedAt != nil }

    func start(subject: Subject?) {
        guard !isActive else { return }
        startedAt = .now
        subjectID = subject?.uuid
        persist()
        blocking.startBlocking()
    }

    /// Ends the running session. Sessions shorter than `minimumDuration` aren't saved.
    func end(in context: ModelContext) {
        guard let startedAt else { return }
        let endedAt = Date.now
        let subject = subjectID.flatMap { fetchSubject(id: $0, in: context) }

        blocking.stopBlocking()
        self.startedAt = nil
        self.subjectID = nil
        persist()

        let duration = endedAt.timeIntervalSince(startedAt)
        let saved = duration >= Self.minimumDuration
        var earnedMinutes = 0.0
        if saved {
            context.insert(FocusSession(startedAt: startedAt, endedAt: endedAt, subject: subject))
            try? context.save()
            earnedMinutes = earned.credit(sessionDuration: duration)
        }
        summary = SessionSummary(
            duration: duration,
            subject: subject,
            saved: saved,
            earnedMinutes: earnedMinutes,
            balanceFull: earned.isBalanceFull,
            focusedToday: focusedToday(in: context)
        )
    }

    func dismissSummary() {
        summary = nil
    }

    func subject(in context: ModelContext) -> Subject? {
        subjectID.flatMap { fetchSubject(id: $0, in: context) }
    }

    private func focusedToday(in context: ModelContext) -> TimeInterval {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= startOfToday })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.duration }
    }

    private func fetchSubject(id: UUID, in context: ModelContext) -> Subject? {
        var descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func persist() {
        defaults.set(startedAt, forKey: Keys.startedAt)
        defaults.set(subjectID?.uuidString, forKey: Keys.subjectID)
    }
}
