import Foundation
import SwiftData
import DeviceActivity

/// Owns the currently running focus session.
///
/// The running session is kept in UserDefaults so it survives the app being
/// closed or killed. Shields stay on in the meantime because ManagedSettings
/// persists them at the system level.
///
/// In Pomodoro mode apps unlock during breaks: while the app is open `refresh()`
/// switches the block at each phase change, and FlowstateMonitor does it when the
/// app is closed, from break schedules handed to iOS ahead of time.
@MainActor
@Observable
final class SessionManager {
    /// Sessions shorter than this are treated as accidental and discarded.
    static let minimumDuration: TimeInterval = 10
    /// How many upcoming breaks are scheduled with iOS at once. Topped up whenever the app opens.
    private static let scheduledBreaks = 4

    private(set) var startedAt: Date?
    private(set) var subjectID: UUID?
    /// Set when the session is in Pomodoro mode; nil for a plain stopwatch.
    private(set) var pomodoro: PomodoroConfig?
    /// True during a break that couldn't be unlocked because iOS didn't accept the timer to block again.
    private(set) var breakStaysBlocked = false

    /// The phase the focus block was last set for, so it's only rewritten when the phase changes.
    private var blockedPhase: PomodoroConfig.Phase?

    private let blocking: BlockingManager
    private let earned: EarnedTimeManager
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let startedAt = "activeSession.startedAt"
        static let subjectID = "activeSession.subjectID"
        static let pomodoro = "activeSession.pomodoro"
    }

    init(blocking: BlockingManager, earned: EarnedTimeManager) {
        self.blocking = blocking
        self.earned = earned
        startedAt = defaults.object(forKey: Keys.startedAt) as? Date
        subjectID = defaults.string(forKey: Keys.subjectID).flatMap(UUID.init)
        pomodoro = defaults.data(forKey: Keys.pomodoro).flatMap { try? JSONDecoder().decode(PomodoroConfig.self, from: $0) }

        // Never leave apps blocked without a session the user can end.
        if !isActive { blocking.stopBlocking() }
        refresh()
    }

    var isActive: Bool { startedAt != nil }

    func start(subject: Subject?, pomodoro: PomodoroConfig? = nil) {
        guard !isActive else { return }
        let now = Date.now
        startedAt = now
        subjectID = subject?.uuid
        self.pomodoro = pomodoro
        persist()
        blocking.startBlocking()
        if let pomodoro {
            blockedPhase = .focus
            scheduleBreaks()
            PomodoroNotifications.schedule(pomodoro, from: now)
        }
    }

    /// Ends the running session and saves its focus time. In Pomodoro mode each
    /// focus block becomes its own session; breaks aren't counted.
    func end(in context: ModelContext) {
        guard let startedAt else { return }
        let endedAt = Date.now
        let subject = subjectID.flatMap { fetchSubject(id: $0, in: context) }
        let blocks = pomodoro?.focusBlocks(from: startedAt, to: endedAt) ?? [(startedAt, endedAt)]

        blocking.stopBlocking()
        stopScheduledBreaks()
        PomodoroNotifications.cancel()
        self.startedAt = nil
        self.subjectID = nil
        self.pomodoro = nil
        blockedPhase = nil
        breakStaysBlocked = false
        persist()

        for block in blocks where block.end.timeIntervalSince(block.start) >= Self.minimumDuration {
            let session = FocusSession(startedAt: block.start, endedAt: block.end, subject: subject)
            context.insert(session)
            earned.credit(sessionDuration: session.duration)
        }
        try? context.save()
    }

    /// Call regularly while the app is open: lifts the block for Pomodoro breaks and restores it after.
    func refresh(now: Date = .now) {
        guard let startedAt, let pomodoro else { return }
        let state = pomodoro.state(elapsed: now.timeIntervalSince(startedAt))
        guard state.phase != blockedPhase else { return }
        blockedPhase = state.phase
        switch state.phase {
        case .focus:
            breakStaysBlocked = false
            blocking.startBlocking()
        case .rest:
            // Only open apps if iOS will block them again when the break ends, even with flowstate closed.
            if canLiftBreak(round: state.round - 1, now: now) {
                blocking.liftForBreak()
            } else {
                breakStaysBlocked = true
            }
        }
    }

    /// Call when the app comes to the foreground.
    func appBecameActive() {
        scheduleBreaks()
        // Re-apply the block for the current phase, whatever happened while the app was away.
        blockedPhase = nil
        refresh()
    }

    func subject(in context: ModelContext) -> Subject? {
        subjectID.flatMap { fetchSubject(id: $0, in: context) }
    }

    // MARK: - Private

    /// Hands the next few breaks to iOS so FlowstateMonitor can unlock and re-block
    /// apps on time while flowstate is closed. If the app stays closed past the last
    /// one, apps simply stay blocked.
    private func scheduleBreaks(now: Date = .now) {
        guard ScreenTime.isAvailable, blocking.isAuthorized, let startedAt, let pomodoro else { return }
        stopScheduledBreaks()
        let center = DeviceActivityCenter()
        let currentRound = Int(max(0, now.timeIntervalSince(startedAt)) / pomodoro.cycle)
        for round in currentRound..<(currentRound + Self.scheduledBreaks) {
            let breakStart = startedAt.addingTimeInterval(Double(round) * pomodoro.cycle + pomodoro.focus)
            let breakEnd = startedAt.addingTimeInterval(Double(round + 1) * pomodoro.cycle)
            if breakStart > now {
                try? center.startMonitoring({ .pomodoroBreak(round, short: $0) }, from: breakStart, to: breakEnd)
            } else if breakEnd > now {
                try? center.startMonitoring({ .pomodoroRelock(round, short: $0) }, from: now, to: breakEnd)
            }
        }
    }

    /// Whether the block can be lifted for this break: iOS must be set to restore it at the break's end.
    private func canLiftBreak(round: Int, now: Date) -> Bool {
        // Nothing is blocked without Screen Time, so there's nothing to restore.
        guard ScreenTime.isAvailable, blocking.isAuthorized, let startedAt, let pomodoro else { return true }
        let center = DeviceActivityCenter()
        if center.activities.contains(where: { $0.pomodoroRound == round }) { return true }
        let breakEnd = startedAt.addingTimeInterval(Double(round + 1) * pomodoro.cycle)
        do {
            try center.startMonitoring({ .pomodoroRelock(round, short: $0) }, from: now, to: breakEnd)
            return true
        } catch {
            return false
        }
    }

    private func stopScheduledBreaks() {
        guard ScreenTime.isAvailable else { return }
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter(\.isPomodoro))
    }

    private func fetchSubject(id: UUID, in context: ModelContext) -> Subject? {
        var descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func persist() {
        defaults.set(startedAt, forKey: Keys.startedAt)
        defaults.set(subjectID?.uuidString, forKey: Keys.subjectID)
        defaults.set(pomodoro.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.pomodoro)
    }
}
