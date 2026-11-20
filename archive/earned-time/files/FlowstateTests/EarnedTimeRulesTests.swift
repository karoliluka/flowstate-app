import Foundation
import Testing
@testable import Flowstate

@MainActor
struct EarnedTimeRulesTests {
    @Test func firstHalfHourCostsOneToOne() {
        #expect(EarnedTimeManager.cost(forMinutes: 15, unlockedToday: 0) == 15)
        #expect(EarnedTimeManager.cost(forMinutes: 30, unlockedToday: 0) == 30)
    }

    @Test func priceRisesAcrossTiers() {
        // 15 min at 1× (to reach 30), then 15 min at 1.5×.
        #expect(EarnedTimeManager.cost(forMinutes: 30, unlockedToday: 15) == 15 + 22.5)
        // 60 min from scratch: 30 at 1× + 30 at 1.5×.
        #expect(EarnedTimeManager.cost(forMinutes: 60, unlockedToday: 0) == 75)
        // Past an hour everything costs 2×.
        #expect(EarnedTimeManager.cost(forMinutes: 15, unlockedToday: 90) == 30)
    }

    @Test func onlyEasierModesWaitForTheCooldown() {
        #expect(EarnMode.gentle.isEasier(than: .balanced))
        #expect(EarnMode.balanced.isEasier(than: .strict))
        #expect(!EarnMode.strict.isEasier(than: .gentle))
        #expect(!EarnMode.balanced.isEasier(than: .balanced))
    }

    @Test func easierModesEarnFasterAndSaveMore() {
        for (easier, harder) in [(EarnMode.gentle, EarnMode.balanced), (.balanced, .strict)] {
            #expect(easier.focusPerMinute < harder.focusPerMinute)
            #expect(easier.cap > harder.cap)
        }
    }
}
