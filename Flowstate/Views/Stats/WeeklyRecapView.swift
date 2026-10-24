import SwiftUI
import SwiftData
import Charts

/// A week at a glance: total and change from last week, a day-by-day chart, highlights,
/// comparisons and the subject breakdown. Opened from the weekly recap notification or Stats.
struct WeeklyRecapView: View {
    let week: DateInterval

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]

    init(weekStart: Date) {
        let calendar = Calendar.current
        week = calendar.dateInterval(of: .weekOfYear, for: weekStart)!
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start)!
        let end = week.end
        _sessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= lastWeekStart && $0.startedAt < end }, sort: \.startedAt)
    }

    private struct DayBar: Identifiable {
        let day: Date
        let subjectKey: String
        let duration: TimeInterval
        var id: String { "\(day.timeIntervalSince1970)-\(subjectKey)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = sessions.filter { $0.startedAt >= week.start }
        let lastWeek = sessions.filter { $0.startedAt < week.start }
        let total = thisWeek.reduce(0) { $0 + $1.duration }
        let lastTotal = lastWeek.reduce(0) { $0 + $1.duration }
        let days = DayFocus.byDay(thisWeek, calendar: calendar)
        let subjects = SubjectBreakdown.totals(thisWeek)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(week.start.formatted(.dateTime.day().month(.abbreviated)) + " – " + calendar.date(byAdding: .day, value: -1, to: week.end)!.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(total.focusFormatted)
                            .font(.system(size: 64, weight: .light, design: .rounded))
                            .monospacedDigit()
                        changeLabel(total: total, lastTotal: lastTotal)
                    }

                    if thisWeek.isEmpty {
                        ContentUnavailableView("No focus this week yet", systemImage: "chart.bar", description: Text("Your recap fills up as you focus."))
                    } else {
                        weekChart(thisWeek: thisWeek, subjects: subjects, calendar: calendar)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatTile(title: "Top subject", value: subjects.first?.name ?? "–")
                            StatTile(title: "Best day", value: days.max { $0.value.total < $1.value.total }.map { $0.key.formatted(.dateTime.weekday(.wide)) } ?? "–")
                            StatTile(title: "Sessions", value: "\(thisWeek.count)")
                            StatTile(title: "Days focused", value: "\(days.count) of 7")
                        }

                        section("That's like") { ComparisonCards(total: total) }
                        section("By subject") { SubjectBreakdown(sessions: thisWeek) }
                    }
                }
                .padding()
            }
            .navigationTitle("Your week in focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func changeLabel(total: TimeInterval, lastTotal: TimeInterval) -> some View {
        if lastTotal > 0 {
            let change = Int(((total - lastTotal) / lastTotal * 100).rounded())
            Label(
                change == 0 ? "Same as last week" : "\(abs(change))% \(change > 0 ? "more" : "less") than last week",
                systemImage: change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "equal")
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(change >= 0 ? .primary : .secondary)
        } else {
            Text("Your first week in the recap")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func weekChart(thisWeek: [FocusSession], subjects: [SubjectBreakdown.Total], calendar: Calendar) -> some View {
        var totals: [String: DayBar] = [:]
        for session in thisWeek {
            let day = calendar.startOfDay(for: session.startedAt)
            let key = session.subject?.uuid.uuidString ?? "none"
            let id = "\(day.timeIntervalSince1970)-\(key)"
            totals[id] = DayBar(day: day, subjectKey: key, duration: (totals[id]?.duration ?? 0) + session.duration)
        }

        return Chart(Array(totals.values)) { bar in
            BarMark(
                x: .value("Day", bar.day, unit: .day),
                y: .value("Hours", bar.duration / 3600)
            )
            .foregroundStyle(by: .value("Subject", bar.subjectKey))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: subjects.map(\.id), range: subjects.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: week.start...week.end)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours.formatted())h") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: 150)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
    }
}
