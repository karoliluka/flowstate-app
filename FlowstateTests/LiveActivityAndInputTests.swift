import Foundation
import Testing
@testable import Flowstate

/// The Live Activity's goals, and how forgiving subject names are.
struct LiveActivityAndInputTests {
    private let minute: TimeInterval = 60
    static let elapsedTimes: [TimeInterval] = [0, 420, 3000, 10_800, 27_000]

    @Test(arguments: elapsedTimes)
    func goalsLieAheadSoonestFirst(elapsed: TimeInterval) {
        let goals = FocusComparisons.goals(after: elapsed, seed: 7)
        #expect(!goals.isEmpty)
        #expect(goals.count <= 3)
        #expect(goals.allSatisfy { $0.reachedAfter > elapsed })
        #expect(goals.map(\.reachedAfter) == goals.map(\.reachedAfter).sorted())
        #expect(Set(goals.map(\.comparison.id)).count == goals.count)
        for goal in goals {
            #expect(goal.reachedAfter == Double(goal.count) * goal.comparison.duration)
        }
    }

    @Test func goalsFallInTheirWindows() {
        let goals = FocusComparisons.goals(after: 10 * minute, seed: 3)
        #expect(goals.count == 3)
        for (goal, window) in zip(goals, FocusComparisons.goalWindows) {
            #expect(window.contains(goal.reachedAfter - 10 * minute))
        }
    }

    @Test func sameSessionKeepsTheSameGoals() {
        let first = FocusComparisons.goals(after: 20 * minute, seed: 99).map(\.comparison.id)
        #expect(first == FocusComparisons.goals(after: 20 * minute, seed: 99).map(\.comparison.id))
    }

    @Test func everyComparisonHasAShortEnoughName() {
        // Three goals share the Lock Screen's width.
        for comparison in FocusComparisons.catalog {
            #expect(comparison.shortName.count <= 18, "\(comparison.id): \(comparison.shortName)")
        }
    }

    @Test func namesAreAcceptedHoweverTheyAreTyped() {
        #expect(SubjectEditor.normalizedName("  calculus   2 ") == "calculus 2")
        #expect(SubjectEditor.normalizedName("Spanish\n\tvocab") == "Spanish vocab")
        #expect(SubjectEditor.normalizedName("   ").isEmpty)
    }

    @Test func duplicateNamesIgnoreCaseAccentsAndSpaces() {
        #expect(SubjectEditor.sameName("Biology", " biology "))
        #expect(SubjectEditor.sameName("Español", "espanol"))
        #expect(!SubjectEditor.sameName("Bio", "Biology"))
    }
}
