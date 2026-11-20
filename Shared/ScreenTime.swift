import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

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

/// Screen Time selections, stored in the App Group (kept there for extensions).
enum SharedSettings {
    static let appGroup = "group.com.lukakaroli.flowstate"
    static let allowedKey = "allowedSelection"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
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

/// Earned scrolling time is switched off for now (see archive/earned-time/RESTORE.md).
/// Its block lived in its own store, and iOS keeps shields across app updates, so it is cleared
/// on launch; otherwise distracting apps would stay blocked with no way to unlock them.
enum RetiredEarnedShield {
    static func clear() {
        guard ScreenTime.isAvailable else { return }
        ManagedSettingsStore(named: ManagedSettingsStore.Name("earned")).clearAllSettings()
        // Unlock timers were the only activities flowstate monitored.
        DeviceActivityCenter().stopMonitoring()
    }
}

extension Set {
    /// At most `ScreenTime.maxTokens` elements: iOS ignores a larger set entirely,
    /// so dropping the extras keeps the rest blocked instead of nothing.
    func limited() -> Set {
        count <= ScreenTime.maxTokens ? self : Set(prefix(ScreenTime.maxTokens))
    }
}
