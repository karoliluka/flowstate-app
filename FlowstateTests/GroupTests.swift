import Foundation
import Testing
@testable import Flowstate

/// Study group logic that runs on the phone: invite links and the numbers shared with group mates.
struct GroupTests {
    @Test func invitesOpenFromEitherKindOfLink() {
        #expect(InviteLink.code(from: URL(string: "flowstate://join/ab12cd34")!) == "AB12CD34")
        #expect(InviteLink.code(from: URL(string: "https://flowstate-groups.vercel.app/join/AB12CD34")!) == "AB12CD34")
        #expect(InviteLink.code(from: URL(string: "flowstate://auth-callback#access_token=x")!) == nil)
    }

    @Test func pastedInvitesAreAcceptedHoweverTheyArrive() {
        let message = InviteLink.shareMessage(groupName: "Physics crew", code: "AB12CD34")
        #expect(InviteLink.code(fromText: message) == "AB12CD34")
        #expect(InviteLink.code(fromText: "  ab12 cd34 ") == "AB12CD34")
        #expect(InviteLink.code(fromText: "Join here: https://x.vercel.app/join/AB12CD34.") == "AB12CD34")
        #expect(InviteLink.code(fromText: "see you at the library tomorrow") == nil)
        #expect(InviteLink.code(fromText: "ab!") == nil)
    }

    @Test func weeksRunMondayToSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 0, minute: 30))!
        #expect(GroupStats.weekStartString(for: sunday) == "2026-11-16")
        #expect(GroupStats.weekStartString(for: monday) == "2026-11-23")
    }

    @Test func totalsSplitThisWeekFromAllTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 10))! }
        let totals = GroupStats.totals(of: [(day(13), 3600), (day(16), 1800), (day(19), 600)], now: day(20))
        #expect(totals.total == 6000)
        #expect(totals.thisWeek == 2400)
        #expect(totals.weekStart == "2026-11-16")
    }

    @Test func lastWeeksNumbersCountAsZeroAndStaleSessionsAsInactive() {
        let now = Date.now
        var member = MemberProfile(id: UUID(), firstName: "Ana", lastName: "", totalSeconds: 9000,
                                   weekStart: "2001-01-01", weekSeconds: 5000, activeSince: now.addingTimeInterval(-600))
        #expect(member.secondsThisWeek(now: now) == 0)
        member.weekStart = GroupStats.weekStartString(for: now)
        #expect(member.secondsThisWeek(now: now) == 5000)
        #expect(member.isActive(now: now))
        member.activeSince = now.addingTimeInterval(-13 * 3600)
        #expect(!member.isActive(now: now))
        #expect(member.displayName == "Ana")
    }
}
