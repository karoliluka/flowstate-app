import Foundation

/// Alternating focus and break phases, repeating until the user ends the session.
struct PomodoroConfig: Codable, Equatable {
    var focusMinutes: Int
    var breakMinutes: Int

    static let presets: [PomodoroConfig] = [
        .init(focusMinutes: 25, breakMinutes: 5),
        .init(focusMinutes: 50, breakMinutes: 10),
        .init(focusMinutes: 90, breakMinutes: 15),
    ]

    // Clamped so a bad stored value can't make a zero-length cycle (and an endless loop).
    var focus: TimeInterval { Double(max(1, focusMinutes)) * 60 }
    var rest: TimeInterval { Double(max(0, breakMinutes)) * 60 }
    var cycle: TimeInterval { focus + rest }

    enum Phase: Equatable {
        case focus, rest
    }

    struct State {
        let phase: Phase
        /// 1-based.
        let round: Int
        let remaining: TimeInterval
        /// Total focus time so far, breaks excluded.
        let focused: TimeInterval
    }

    func state(elapsed: TimeInterval) -> State {
        let elapsed = max(0, elapsed)
        let completedRounds = Int(elapsed / cycle)
        let intoRound = elapsed - Double(completedRounds) * cycle
        let focused = Double(completedRounds) * focus + min(intoRound, focus)
        return intoRound < focus
            ? State(phase: .focus, round: completedRounds + 1, remaining: focus - intoRound, focused: focused)
            : State(phase: .rest, round: completedRounds + 1, remaining: cycle - intoRound, focused: focused)
    }

    /// The focus blocks between `start` and `end`, each saved as its own session.
    func focusBlocks(from start: Date, to end: Date) -> [(start: Date, end: Date)] {
        var blocks: [(start: Date, end: Date)] = []
        var blockStart = start
        while blockStart < end {
            blocks.append((blockStart, min(end, blockStart.addingTimeInterval(focus))))
            blockStart = blockStart.addingTimeInterval(cycle)
        }
        return blocks
    }

    var summary: String {
        "\(focusMinutes) min focus · \(breakMinutes) min break"
    }
}
