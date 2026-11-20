import DeviceActivity

/// iOS wakes this extension when earned time runs out, even if flowstate is closed.
final class FlowstateMonitor: DeviceActivityMonitor {
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        if activity.isUnlock && activity.endsAtWarning {
            EarnedShield.apply()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.isUnlock && !activity.endsAtWarning {
            EarnedShield.apply()
        }
    }
}
