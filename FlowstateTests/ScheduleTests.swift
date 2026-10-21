import Foundation
import DeviceActivity
import Testing
@testable import Flowstate

/// The windows handed to iOS decide when apps are blocked again, so their math has to be exact.
struct ScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func shortWindowIsStretchedAndWarnsAtTheRealEnd() throws {
        let end = start.addingTimeInterval(5 * 60)
        let window = DeviceActivitySchedule.window(from: start, to: end, calendar: calendar)

        #expect(window.isShort)
        #expect(calendar.date(from: window.schedule.intervalStart) == start)
        #expect(calendar.date(from: window.schedule.intervalEnd) == start.addingTimeInterval(15 * 60))
        // Warning fires 10 minutes before the stretched end, which is exactly the real end.
        let warning = try #require(window.schedule.warningTime)
        #expect(warning.minute == 10 && warning.second == 0)
        #expect(window.schedule.repeats == false)
    }

    @Test func oddLengthsKeepSecondPrecision() throws {
        let end = start.addingTimeInterval(7 * 60 + 30)
        let window = DeviceActivitySchedule.window(from: start, to: end, calendar: calendar)
        let warning = try #require(window.schedule.warningTime)
        #expect(warning.minute == 7 && warning.second == 30)
    }

    @Test func longWindowEndsExactlyWithoutWarning() {
        let end = start.addingTimeInterval(30 * 60)
        let window = DeviceActivitySchedule.window(from: start, to: end, calendar: calendar)

        #expect(!window.isShort)
        #expect(calendar.date(from: window.schedule.intervalEnd) == end)
        #expect(window.schedule.warningTime == nil)
    }

    @Test func exactlyFifteenMinutesIsNotShort() {
        let window = DeviceActivitySchedule.window(from: start, to: start.addingTimeInterval(15 * 60), calendar: calendar)
        #expect(!window.isShort)
    }

    @Test func activityNamesTellTheExtensionWhatToDo() {
        let shortBreak = DeviceActivityName.pomodoroBreak(3, short: true)
        #expect(shortBreak.isPomodoro && shortBreak.isPomodoroBreak && shortBreak.endsAtWarning)
        #expect(shortBreak.pomodoroRound == 3)
        #expect(!shortBreak.isUnlock)

        let relock = DeviceActivityName.pomodoroRelock(12, short: false)
        #expect(relock.isPomodoro && !relock.isPomodoroBreak && !relock.endsAtWarning)
        #expect(relock.pomodoroRound == 12)

        let pass = DeviceActivityName.unlock(short: true)
        #expect(pass.isUnlock && pass.endsAtWarning && !pass.isPomodoro)
        #expect(pass.pomodoroRound == nil)
        #expect(DeviceActivityName.allUnlocks.allSatisfy { $0.isUnlock })
    }
}
