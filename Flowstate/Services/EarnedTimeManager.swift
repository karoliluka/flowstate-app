import Foundation
import FamilyControls
import DeviceActivity

enum EarnMode: String, CaseIterable, Identifiable, Codable {
    case gentle, balanced, strict

    var id: Self { self }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .strict: "Strict"
        }
    }

    /// Minutes of focus needed to earn one minute of scrolling.
    var focusPerMinute: Double {
        switch self {
        case .gentle: 2
        case .balanced: 3
        case .strict: 4
        }
    }

    /// The most scrolling time that can be saved up, in minutes.
    var cap: Double {
        switch self {
        case .gentle: 90
        case .balanced: 60
        case .strict: 30
        }
    }

    func isEasier(than other: EarnMode) -> Bool {
        focusPerMinute < other.focusPerMinute
    }
}

/// Focus earns scrolling time; distracting apps stay blocked until the user spends it.
///
/// Rules:
/// - Every `focusPerMinute` minutes of focus earn 1 minute (sessions of 45+ min earn 1.5×).
/// - The balance is capped per mode, so it can't be hoarded.
/// - Unlocking gets pricier the more you've unlocked today (1× → 1.5× → 2×).
/// - Three free 5-minute emergency passes a day.
/// - Loosening the rules (easier mode, fewer distracting apps) takes effect after a
///   10-minute cooldown, so it can't be an impulse decision. Tightening is instant.
@MainActor
@Observable
final class EarnedTimeManager {
    static let deepFocusThreshold: TimeInterval = 45 * 60
    static let deepFocusBonus = 1.5
    static let passesPerDay = 3
    static let passMinutes = 5.0
    /// iOS can't schedule monitoring windows shorter than 15 minutes, so that's the shortest unlock.
    static let unlockOptions: [Double] = [15, 30, 60]
    static let priceTiers: [(upTo: Double, rate: Double)] = [(30, 1), (60, 1.5), (.infinity, 2)]
    static let loosenDelay: TimeInterval = 10 * 60

    struct Unlock: Codable {
        var endsAt: Date
        var minutes: Double
        var cost: Double
    }

    struct PendingMode: Codable {
        var mode: EarnMode
        var at: Date
    }

    struct PendingApps: Codable {
        var selection: FamilyActivitySelection
        var at: Date
    }

    /// Minutes of scrolling available.
    private(set) var balance: Double
    /// Minutes unlocked with earned time today (passes don't count).
    private(set) var unlockedToday: Double
    private(set) var passesUsedToday: Int
    private(set) var activeUnlock: Unlock?
    private(set) var scheduleError: String?
    private(set) var pendingMode: PendingMode?
    private(set) var pendingDistracting: PendingApps?

    private(set) var mode: EarnMode {
        didSet {
            balance = min(balance, mode.cap)
            save()
        }
    }

    private(set) var distracting: FamilyActivitySelection {
        didSet {
            SharedSettings.saveDistracting(distracting)
            if !isUnlocked { EarnedShield.apply() }
        }
    }

    private var day: Date
    /// The app's own defaults, so the balance survives switching between Preview and full builds.
    /// Only the distracting-apps selection lives in the App Group, for the extension.
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let balance = "earned.balance"
        static let unlockedToday = "earned.unlockedToday"
        static let passesUsedToday = "earned.passesUsedToday"
        static let activeUnlock = "earned.activeUnlock"
        static let mode = "earned.mode"
        static let day = "earned.day"
        static let pendingMode = "earned.pendingMode"
        static let pendingDistracting = "earned.pendingDistracting"
    }

    init() {
        balance = defaults.double(forKey: Keys.balance)
        unlockedToday = defaults.double(forKey: Keys.unlockedToday)
        passesUsedToday = defaults.integer(forKey: Keys.passesUsedToday)
        activeUnlock = Self.decode(Unlock.self, from: defaults.data(forKey: Keys.activeUnlock))
        mode = defaults.string(forKey: Keys.mode).flatMap(EarnMode.init) ?? .balanced
        day = defaults.object(forKey: Keys.day) as? Date ?? Calendar.current.startOfDay(for: .now)
        pendingMode = Self.decode(PendingMode.self, from: defaults.data(forKey: Keys.pendingMode))
        pendingDistracting = Self.decode(PendingApps.self, from: defaults.data(forKey: Keys.pendingDistracting))
        distracting = SharedSettings.loadDistracting()

        resetIfNewDay()
        applyDuePendingChanges()
        if !isUnlocked {
            activeUnlock = nil
            EarnedShield.apply()
        }
    }

    var isEnabled: Bool {
        MarketingMode.isOn ||
        !distracting.applicationTokens.isEmpty || !distracting.categoryTokens.isEmpty || !distracting.webDomainTokens.isEmpty
    }

    var isUnlocked: Bool {
        activeUnlock.map { $0.endsAt > .now } ?? false
    }

    var passesLeft: Int {
        max(0, Self.passesPerDay - passesUsedToday)
    }

    /// How many apps, categories and websites the pending change will stop blocking.
    var pendingRemovalCount: Int {
        guard let pending = pendingDistracting?.selection else { return 0 }
        return distracting.applicationTokens.subtracting(pending.applicationTokens).count
            + distracting.categoryTokens.subtracting(pending.categoryTokens).count
            + distracting.webDomainTokens.subtracting(pending.webDomainTokens).count
    }

    // MARK: - Earning

    /// Scrolling minutes earned for a session of this length.
    func earned(for duration: TimeInterval) -> Double {
        let minutes = duration / 60 / mode.focusPerMinute
        return duration >= Self.deepFocusThreshold ? minutes * Self.deepFocusBonus : minutes
    }

    /// Adds a session's earnings. Returns the minutes actually added, which is less once the balance is full.
    @discardableResult
    func credit(sessionDuration duration: TimeInterval) -> Double {
        resetIfNewDay()
        let before = balance
        balance = min(mode.cap, balance + earned(for: duration))
        save()
        return balance - before
    }

    var isBalanceFull: Bool {
        balance >= mode.cap - 0.001
    }

    // MARK: - Spending

    /// What unlocking `minutes` more costs after `unlockedToday` minutes, given the price tiers.
    static func cost(forMinutes minutes: Double, unlockedToday: Double) -> Double {
        var remaining = minutes
        var used = unlockedToday
        var cost = 0.0
        for tier in priceTiers where remaining > 0 {
            let take = min(max(0, tier.upTo - used), remaining)
            cost += take * tier.rate
            used += take
            remaining -= take
        }
        return cost
    }

    func cost(forMinutes minutes: Double) -> Double {
        Self.cost(forMinutes: minutes, unlockedToday: unlockedToday)
    }

    func canAfford(_ minutes: Double) -> Bool {
        cost(forMinutes: minutes) <= balance + 0.001
    }

    /// The current per-minute price multiplier.
    var currentRate: Double {
        Self.priceTiers.first { unlockedToday < $0.upTo }?.rate ?? 1
    }

    func unlock(minutes: Double) {
        resetIfNewDay()
        guard !isUnlocked, canAfford(minutes) else { return }
        let cost = cost(forMinutes: minutes)
        guard begin(Unlock(endsAt: .now.addingTimeInterval(minutes * 60), minutes: minutes, cost: cost)) else { return }
        balance = max(0, balance - cost)
        unlockedToday += minutes
        save()
    }

    func useEmergencyPass() {
        resetIfNewDay()
        guard !isUnlocked, passesLeft > 0 else { return }
        guard begin(Unlock(endsAt: .now.addingTimeInterval(Self.passMinutes * 60), minutes: Self.passMinutes, cost: 0)) else { return }
        passesUsedToday += 1
        save()
    }

    /// Re-blocks early and refunds the unused share of what was paid.
    func lockNow() {
        guard let unlock = activeUnlock else { return }
        let remainingFraction = min(1, max(0, unlock.endsAt.timeIntervalSinceNow / (unlock.minutes * 60)))
        balance = min(mode.cap, balance + unlock.cost * remainingFraction)
        if unlock.cost > 0 {
            unlockedToday = max(0, unlockedToday - unlock.minutes * remainingFraction)
        }
        if ScreenTime.isAvailable {
            DeviceActivityCenter().stopMonitoring(DeviceActivityName.allUnlocks)
        }
        endUnlock()
    }

    // MARK: - Changing the rules

    /// Stricter modes apply right away; easier ones after `loosenDelay`.
    /// Picking the current mode cancels a pending change.
    func requestMode(_ newMode: EarnMode) {
        if newMode.isEasier(than: mode) {
            pendingMode = PendingMode(mode: newMode, at: .now.addingTimeInterval(Self.loosenDelay))
            save()
        } else {
            pendingMode = nil
            mode = newMode
        }
    }

    /// Newly added apps are blocked right away; removed ones stay blocked for `loosenDelay`.
    func requestDistracting(_ selection: FamilyActivitySelection) {
        let removesSomething = !distracting.applicationTokens.isSubset(of: selection.applicationTokens)
            || !distracting.categoryTokens.isSubset(of: selection.categoryTokens)
            || !distracting.webDomainTokens.isSubset(of: selection.webDomainTokens)

        if removesSomething {
            var blockedNow = distracting
            blockedNow.applicationTokens.formUnion(selection.applicationTokens)
            blockedNow.categoryTokens.formUnion(selection.categoryTokens)
            blockedNow.webDomainTokens.formUnion(selection.webDomainTokens)
            pendingDistracting = PendingApps(selection: selection, at: .now.addingTimeInterval(Self.loosenDelay))
            distracting = blockedNow
        } else {
            pendingDistracting = nil
            distracting = selection
        }
        save()
    }

    func cancelPendingMode() {
        pendingMode = nil
        save()
    }

    func cancelPendingDistracting() {
        pendingDistracting = nil
        save()
    }

    /// Call regularly while the app is open; applies due rule changes and re-blocks if the unlock has run out.
    func refresh() {
        resetIfNewDay()
        applyDuePendingChanges()
        if let unlock = activeUnlock, unlock.endsAt <= .now {
            endUnlock()
        }
    }

    #if DEBUG
    func debugAddBalance(_ minutes: Double) {
        balance = min(mode.cap, balance + minutes)
        save()
    }
    #endif

    // MARK: - Private

    /// Hands the re-block to iOS before opening anything, so an unlock can't outlive its time
    /// even if flowstate is closed. Returns false (and keeps apps blocked) if iOS refuses.
    private func begin(_ unlock: Unlock) -> Bool {
        do {
            try scheduleRelock(at: unlock.endsAt)
        } catch {
            scheduleError = "Couldn't unlock: iOS didn't accept the timer that blocks apps again. \(error.localizedDescription)"
            return false
        }
        scheduleError = nil
        activeUnlock = unlock
        save()
        EarnedShield.liftForUnlock()
        return true
    }

    private func endUnlock() {
        activeUnlock = nil
        save()
        EarnedShield.apply()
    }

    /// Wakes FlowstateMonitor when the unlock ends, even if the app is closed.
    private func scheduleRelock(at end: Date) throws {
        guard ScreenTime.isAvailable else { return }
        let center = DeviceActivityCenter()
        center.stopMonitoring(DeviceActivityName.allUnlocks)
        try center.startMonitoring({ .unlock(short: $0) }, from: .now, to: end)
    }

    private func applyDuePendingChanges(now: Date = .now) {
        if let pending = pendingMode, pending.at <= now {
            pendingMode = nil
            mode = pending.mode
        }
        if let pending = pendingDistracting, pending.at <= now {
            pendingDistracting = nil
            distracting = pending.selection
            save()
        }
    }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: .now)
        guard day != today else { return }
        day = today
        unlockedToday = 0
        passesUsedToday = 0
        save()
    }

    private func save() {
        defaults.set(balance, forKey: Keys.balance)
        defaults.set(unlockedToday, forKey: Keys.unlockedToday)
        defaults.set(passesUsedToday, forKey: Keys.passesUsedToday)
        defaults.set(Self.encode(activeUnlock), forKey: Keys.activeUnlock)
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(day, forKey: Keys.day)
        defaults.set(Self.encode(pendingMode), forKey: Keys.pendingMode)
        defaults.set(Self.encode(pendingDistracting), forKey: Keys.pendingDistracting)
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        value.flatMap { try? JSONEncoder().encode($0) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
