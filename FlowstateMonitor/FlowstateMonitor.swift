import DeviceActivity

/// iOS wakes this extension at scheduled moments, even if flowstate is closed:
/// when earned time runs out, and when Pomodoro breaks start and end.
final class FlowstateMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.isPomodoroBreak {
            FocusShield.liftForBreak()
        }
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        if activity.endsAtWarning {
            finish(activity)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if !activity.endsAtWarning {
            finish(activity)
        }
    }

    /// The real end of an unlock or a break: block again.
    private func finish(_ activity: DeviceActivityName) {
        if activity.isUnlock {
            EarnedShield.apply()
        } else if activity.isPomodoro {
            FocusShield.apply()
        }
    }
}
