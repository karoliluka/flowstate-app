import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    /// Start of today, from RootView; it changes at midnight so the ranges move on.
    let today: Date

    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]
    @AppStorage(StorageKeys.statsRange) private var range: StatsRange = .week
    @Namespace private var calendarZoom
    @Environment(\.comparisonSeed) private var comparisonSeed
    @Environment(NotificationRouter.self) private var router

    var body: some View {
        let stats = Stats(sessions: allSessions, range: range, now: today)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "Focused", value: stats.total.focusFormatted)
                        StatTile(title: "Daily average", value: stats.dailyAverage.focusFormatted)
                        StatTile(title: "Sessions", value: "\(stats.sessions.count)")
                        StatTile(title: "Streak", value: stats.streak == 1 ? "1 day" : "\(stats.streak) days")
                    }

                    if stats.sessions.isEmpty {
                        ContentUnavailableView(
                            "Nothing here yet",
                            systemImage: "chart.bar",
                            description: Text("Finish a focus session and it will show up here.")
                        )
                    } else {
                        if range == .year {
                            section("Every day") {
                                YearHeatmap(months: stats.months, days: stats.dailyFocus, namespace: calendarZoom)
                            }
                        } else {
                            section("Daily focus") { dailyChart(stats) }
                        }
                        if !FocusComparisons.matches(for: stats.total, seed: comparisonSeed).isEmpty {
                            section("That's like") { ComparisonCards(total: stats.total) }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.showRecap(for: today)
                    } label: {
                        Label("Weekly recap", systemImage: "sparkles")
                    }
                }
            }
            .navigationDestination(for: CalendarMonth.self) { month in
                MonthDetailView(month: month, namespace: calendarZoom)
                    .zoomTransition(id: month, in: calendarZoom)
            }
            .navigationDestination(for: CalendarDay.self) { day in
                DayDetailView(day: day)
                    .zoomTransition(id: day, in: calendarZoom)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
    }

    /// One bar per day, stacked by subject.
    private func dailyChart(_ stats: Stats) -> some View {
        Chart(stats.bars) { bar in
            BarMark(
                x: .value("Day", bar.date, unit: .day),
                y: .value("Hours", bar.duration / 3600)
            )
            .foregroundStyle(by: .value("Subject", bar.subjectKey))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: stats.subjects.map(\.id), range: stats.subjects.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: stats.start...stats.end)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours.formatted())h") }
                }
            }
        }
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else {
                // Weekly labels counted back from a few days before the end, so the last one isn't cut off.
                AxisMarks(values: monthLabelDates(stats)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .frame(height: 200)
    }

    private func monthLabelDates(_ stats: Stats) -> [Date] {
        let calendar = Calendar.current
        return (0..<5)
            .compactMap { calendar.date(byAdding: .day, value: -4 - 7 * $0, to: stats.end) }
            .filter { $0 >= stats.start }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Year heatmap

/// Twelve small month calendars. Each day takes the color of the subject focused on most,
/// stronger the longer the day's focus. Tapping a month zooms into it.
private struct YearHeatmap: View {
    let months: [Date]
    let days: [Date: DayFocus]
    let namespace: Namespace.ID

    var body: some View {
        let maxDay = days.values.map(\.total).max() ?? 1

        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 18) {
                ForEach(months, id: \.self) { month in
                    let target = CalendarMonth(start: month)
                    NavigationLink(value: target) {
                        MonthGrid(month: month, days: days, maxDay: maxDay)
                    }
                    .buttonStyle(.plain)
                    .zoomSource(id: target, in: namespace)
                }
            }

            HStack(spacing: 4) {
                Text("Less")
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level == 0 ? Color.primary.opacity(0.07) : Color.primary.opacity(0.25 + 0.75 * level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text("Each day shows the color of the subject you focused on most. Tap a month to see it up close.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MonthGrid: View {
    let month: Date
    let days: [Date: DayFocus]
    let maxDay: TimeInterval

    var body: some View {
        let calendar = Calendar.current
        let dayCount = calendar.range(of: .day, in: .month, for: month)!.count
        let blanks = calendar.leadingBlanks(forMonthStarting: month)
        let today = calendar.startOfDay(for: .now)

        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.month(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<(blanks + dayCount), id: \.self) { index in
                    if index < blanks {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    } else {
                        let day = calendar.date(byAdding: .day, value: index - blanks, to: month)!
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day > today ? HeatmapStyle.future : HeatmapStyle.fill(days[day], maxDay: maxDay))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Calculations

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    func start(from now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today)!
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: today)!
        case .year:
            let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
            return calendar.date(byAdding: .month, value: -11, to: thisMonth)!
        }
    }
}

private struct Stats {
    struct SubjectTotal: Identifiable {
        let id: String
        let name: String
        let color: Color
        let duration: TimeInterval
    }

    struct Bar: Identifiable {
        let date: Date
        let subjectKey: String
        let duration: TimeInterval
        var id: String { "\(date.timeIntervalSince1970)-\(subjectKey)" }
    }

    let start: Date
    let end: Date
    let sessions: [FocusSession]
    let total: TimeInterval
    let dailyAverage: TimeInterval
    let streak: Int
    let subjects: [SubjectTotal]
    let bars: [Bar]
    /// Focus per day, keyed by start of day.
    let dailyFocus: [Date: DayFocus]
    /// Start of each month in the range (used by the year view).
    let months: [Date]

    init(sessions all: [FocusSession], range: StatsRange, now: Date = .now) {
        let calendar = Calendar.current
        let start = range.start(from: now, calendar: calendar)
        self.start = start
        end = calendar.dateInterval(of: .day, for: now)!.end
        let sessions = all.filter { $0.startedAt >= start }
        self.sessions = sessions
        total = sessions.reduce(0) { $0 + $1.duration }

        let days = max(1, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day! + 1)
        dailyAverage = total / Double(days)

        streak = Self.streak(of: all, now: now, calendar: calendar)

        var bySubject: [String: SubjectTotal] = [:]
        var byBar: [String: Bar] = [:]
        for session in sessions {
            let key = session.subject?.uuid.uuidString ?? "none"
            let existing = bySubject[key]?.duration ?? 0
            bySubject[key] = SubjectTotal(
                id: key,
                name: session.subject.displayName,
                color: session.subject.displayColor,
                duration: existing + session.duration
            )

            let day = calendar.startOfDay(for: session.startedAt)

            let barKey = "\(day.timeIntervalSince1970)-\(key)"
            byBar[barKey] = Bar(date: day, subjectKey: key, duration: (byBar[barKey]?.duration ?? 0) + session.duration)
        }
        subjects = bySubject.values.sorted { $0.duration > $1.duration }
        bars = Array(byBar.values)
        dailyFocus = DayFocus.byDay(sessions, calendar: calendar)
        months = range == .year
            ? (0..<12).map { calendar.date(byAdding: .month, value: $0, to: start)! }
            : []
    }

    /// Consecutive days with at least one session, counting back from today
    /// (or from yesterday, so the streak isn't lost before today's session).
    private static func streak(of sessions: [FocusSession], now: Date, calendar: Calendar) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
