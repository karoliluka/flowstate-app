#if DEBUG
import Foundation
import SwiftData

/// Fake subjects and sessions for trying out the app. Debug builds only.
enum SampleData {
    @MainActor
    static func replaceAll(in context: ModelContext) {
        deleteAll(in: context)

        let calendar = Calendar.current
        let now = Date.now
        let subjects = [
            Subject(name: "Math", colorHex: SubjectPalette.hexes[0]),
            Subject(name: "Physics", colorHex: SubjectPalette.hexes[1]),
            Subject(name: "English", colorHex: SubjectPalette.hexes[2]),
            Subject(name: "Reading", colorHex: SubjectPalette.hexes[4]),
            Subject(name: "Side project", colorHex: SubjectPalette.hexes[6]),
        ]
        subjects.forEach(context.insert)

        var generator = SystemRandomNumberGenerator()

        // Past days: most days have 1–3 sessions, with lighter weekends and a summer break.
        for daysAgo in 1...330 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            let isWeekend = calendar.isDateInWeekend(day)
            let month = calendar.component(.month, from: day)
            let chance = (month == 7 || month == 8) ? 0.3 : (isWeekend ? 0.45 : 0.85)
            guard Double.random(in: 0...1, using: &generator) < chance else { continue }

            var start = calendar.date(bySettingHour: Int.random(in: 8...16), minute: Int.random(in: 0...59), second: 0, of: day)!
            for _ in 0..<Int.random(in: 1...3) {
                let minutes = Double(Int.random(in: 15...110))
                let end = start.addingTimeInterval(minutes * 60)
                context.insert(FocusSession(startedAt: start, endedAt: end, subject: subjects.randomElement()))
                start = end.addingTimeInterval(Double(Int.random(in: 20...90)) * 60)
            }
        }

        // Today: a couple of sessions that already ended.
        context.insert(FocusSession(startedAt: now.addingTimeInterval(-4 * 3600), endedAt: now.addingTimeInterval(-3 * 3600), subject: subjects[0]))
        context.insert(FocusSession(startedAt: now.addingTimeInterval(-2 * 3600), endedAt: now.addingTimeInterval(-2 * 3600 + 25 * 60), subject: subjects[3]))

        try? context.save()
    }

    @MainActor
    static func deleteAll(in context: ModelContext) {
        // Delete one by one: SwiftData's batch delete fails on these related models.
        for session in (try? context.fetch(FetchDescriptor<FocusSession>())) ?? [] {
            context.delete(session)
        }
        for subject in (try? context.fetch(FetchDescriptor<Subject>())) ?? [] {
            context.delete(subject)
        }
        try? context.save()
    }
}
#endif
