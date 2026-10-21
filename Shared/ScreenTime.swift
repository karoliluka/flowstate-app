import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// Shared between the app and the FlowstateMonitor extension.

/// Whether Screen Time blocking can be used in this build. The Preview build runs on
/// free Apple accounts, which don't get the Screen Time capability, so blocking is off there.
enum ScreenTime {
    #if PREVIEW
    static let isAvailable = false
    #else
    static let isAvailable = true
    #endif

    /// iOS shields nothing at all when given more than 50 apps, and accepts at most 50 exceptions.
    static let maxTokens = 50
}

/// Settings the extension needs too, stored in the App Group.
enum SharedSettings {
    static let appGroup = "group.com.lukakaroli.flowstate"
    static let distractingKey = "distractingSelection"
    static let allowedKey = "allowedSelection"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func loadDistracting() -> FamilyActivitySelection {
        loadSelection(forKey: distractingKey)
    }

    static func saveDistracting(_ selection: FamilyActivitySelection) {
        saveSelection(selection, forKey: distractingKey)
    }

    /// Picking a category in the allowlist includes its apps, because `.all(except:)` only
    /// takes app tokens. Rebuilt on every load in case decoding drops the flag.
    static func loadAllowed() -> FamilyActivitySelection {
        let stored = loadSelection(forKey: allowedKey)
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = stored.applicationTokens
        selection.categoryTokens = stored.categoryTokens
        selection.webDomainTokens = stored.webDomainTokens
        return selection
    }

    static func saveAllowed(_ selection: FamilyActivitySelection) {
        saveSelection(selection, forKey: allowedKey)
    }

    private static func loadSelection(forKey key: String) -> FamilyActivitySelection {
        guard
            let data = defaults.data(forKey: key),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    private static func saveSelection(_ selection: FamilyActivitySelection, forKey key: String) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key)
    }
}

extension ManagedSettingsStore.Name {
    /// Focus sessions: everything except allowed apps.
    static let focus = Self("focus")
    /// Earned time: the user's distracting apps, unless unlocked.
    static let earned = Self("earned")
}

extension DeviceActivityName {
    private static let unlockBase = "flowstate.unlock"
    private static let shortSuffix = ".short"

    /// Blocks distracting apps again when an unlock or emergency pass ends.
    static func unlock(short: Bool) -> Self {
        Self(unlockBase + (short ? shortSuffix : ""))
    }

    static let allUnlocks: [Self] = [unlock(short: false), unlock(short: true)]

    var isUnlock: Bool { rawValue.hasPrefix(Self.unlockBase) }

    /// Short windows are stretched to the 15-minute minimum and really end at the warning.
    var endsAtWarning: Bool { rawValue.hasSuffix(Self.shortSuffix) }
}

extension DeviceActivitySchedule {
    /// iOS rejects monitoring windows shorter than this.
    static let minimumInterval: TimeInterval = 15 * 60

    /// A one-off window from `start` to `end`. A window shorter than 15 minutes is stretched
    /// to 15 minutes, with a warning time that fires exactly at `end` (Apple's suggested
    /// workaround for `intervalTooShort`). `isShort` says which callback marks the real end.
    static func window(from start: Date, to end: Date, calendar: Calendar = .current) -> (schedule: DeviceActivitySchedule, isShort: Bool) {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let isShort = end.timeIntervalSince(start) < minimumInterval
        let intervalEnd = isShort ? start.addingTimeInterval(minimumInterval) : end
        let warningSeconds = Int(intervalEnd.timeIntervalSince(end).rounded())
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: intervalEnd),
            repeats: false,
            warningTime: isShort ? DateComponents(minute: warningSeconds / 60, second: warningSeconds % 60) : nil
        )
        return (schedule, isShort)
    }
}

extension DeviceActivityCenter {
    /// Monitors a one-off window from `start` to `end`, named by `name(isShort)`.
    func startMonitoring(_ name: (Bool) -> DeviceActivityName, from start: Date, to end: Date) throws {
        let window = DeviceActivitySchedule.window(from: start, to: end)
        try startMonitoring(name(window.isShort), during: window.schedule)
    }
}

/// The focus-session block: everything except the apps the user allowed.
/// While it's on, the clock is locked so a session can't be stretched.
enum FocusShield {
    static func apply() {
        guard ScreenTime.isAvailable else { return }
        let allowed = SharedSettings.loadAllowed()
        let store = ManagedSettingsStore(named: .focus)
        store.shield.applicationCategories = .all(except: allowed.applicationTokens.limited())
        store.shield.webDomainCategories = .all(except: allowed.webDomainTokens.limited())
        store.dateAndTime.requireAutomaticDateAndTime = true
    }

    static func remove() {
        guard ScreenTime.isAvailable else { return }
        ManagedSettingsStore(named: .focus).clearAllSettings()
    }
}

/// The always-on block of distracting apps that earned time temporarily lifts.
enum EarnedShield {
    static func apply() {
        guard ScreenTime.isAvailable else { return }
        let selection = SharedSettings.loadDistracting()
        let store = ManagedSettingsStore(named: .earned)
        let apps = selection.applicationTokens.limited()
        let categories = selection.categoryTokens.limited()
        let domains = selection.webDomainTokens.limited()
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.dateAndTime.requireAutomaticDateAndTime = nil
    }

    /// Opens distracting apps while earned time is spent; the clock is locked so the unlock can't be stretched.
    static func liftForUnlock() {
        guard ScreenTime.isAvailable else { return }
        let store = ManagedSettingsStore(named: .earned)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.dateAndTime.requireAutomaticDateAndTime = true
    }
}

extension Set {
    /// At most `ScreenTime.maxTokens` elements: iOS ignores a larger set entirely,
    /// so dropping the extras keeps the rest blocked instead of nothing.
    func limited() -> Set {
        count <= ScreenTime.maxTokens ? self : Set(prefix(ScreenTime.maxTokens))
    }
}
