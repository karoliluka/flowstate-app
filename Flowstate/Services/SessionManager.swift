import Foundation
import SwiftData

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

        guard endedAt.timeIntervalSince(startedAt) >= Self.minimumDuration else { return }
        let session = FocusSession(startedAt: startedAt, endedAt: endedAt, subject: subject)
        context.insert(session)
        try? context.save()
        earned.credit(sessionDuration: session.duration)
    }

    func subject(in context: ModelContext) -> Subject? {
        subjectID.flatMap { fetchSubject(id: $0, in: context) }
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
