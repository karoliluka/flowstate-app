import Foundation
import Testing
@testable import Flowstate

struct PomodoroConfigTests {
    private let config = PomodoroConfig(focusMinutes: 25, breakMinutes: 5)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func phasesAlternate() {
        let early = config.state(elapsed: 60)
        #expect(early.phase == .focus && early.round == 1 && early.remaining == 24 * 60)

        let inBreak = config.state(elapsed: 26 * 60)
        #expect(inBreak.phase == .rest && inBreak.round == 1 && inBreak.remaining == 4 * 60)
        #expect(inBreak.focused == 25 * 60)

        let secondRound = config.state(elapsed: 31 * 60)
        #expect(secondRound.phase == .focus && secondRound.round == 2)
        #expect(secondRound.focused == 26 * 60)
    }

    @Test func clockGoingBackwardsCountsAsTheStart() {
        let state = config.state(elapsed: -120)
        #expect(state.phase == .focus && state.round == 1 && state.focused == 0)
    }

    @Test func focusBlocksSkipBreaks() {
        let blocks = config.focusBlocks(from: start, to: start.addingTimeInterval(65 * 60))
        #expect(blocks.count == 3)
        #expect(blocks[0].end.timeIntervalSince(blocks[0].start) == 25 * 60)
        #expect(blocks[1].start == start.addingTimeInterval(30 * 60))
        // Ended 5 minutes into the third focus block.
        #expect(blocks[2].end.timeIntervalSince(blocks[2].start) == 5 * 60)
    }

    @Test func endingDuringABreakDoesNotCountTheBreak() {
        let blocks = config.focusBlocks(from: start, to: start.addingTimeInterval(28 * 60))
        #expect(blocks.count == 1)
        #expect(blocks[0].end == start.addingTimeInterval(25 * 60))
    }

    @Test func zeroLengthConfigCannotLoopForever() {
        let broken = PomodoroConfig(focusMinutes: 0, breakMinutes: 0)
        #expect(broken.cycle > 0)
        let blocks = broken.focusBlocks(from: start, to: start.addingTimeInterval(5 * 60))
        #expect(blocks.count == 5)
    }
}
