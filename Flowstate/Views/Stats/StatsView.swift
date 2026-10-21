import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    /// Start of today, from RootView; it changes at midnight so the ranges move on.
    let today: Date

    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]
    @AppStorage(StorageKeys.statsRange) private var range: StatsRange = .week

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
                                YearHeatmap(months: stats.months, dailyTotals: stats.dailyTotals)
                            }
                        } else {
                            section("Daily focus") { dailyChart(stats) }
                        }
                        if !FocusComparisons.matches(for: stats.total).isEmpty {
                            section("That's like") { ComparisonCards(total: stats.total) }
                        }
                        section("By subject") { breakdown(stats) }
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
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

    private func breakdown(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(stats.subjects) { subject in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(subject.color).frame(width: 8, height: 8)
                        Text(subject.name)
                        Spacer()
                        Text(subject.duration.focusFormatted)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(subject.color)
                            .frame(width: geometry.size.width * subject.duration / max(stats.total, 1))
                    }
                    .frame(height: 4)
                }
            }
        }
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

// MARK: - Comparisons

/// Swipeable cards comparing focus time with everyday things.
private struct ComparisonCards: View {
    let total: TimeInterval

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(FocusComparisons.matches(for: total), id: \.comparison.id) { match in
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: match.comparison.icon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(FocusComparisons.formatCount(match.count) + "×")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(match.comparison.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2, reservesSpace: true)
                        Text(match.comparison.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.62 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - Year heatmap

/// Twelve small month calendars; the darker a day, the longer you focused.
private struct YearHeatmap: View {
    let months: [Date]
    let dailyTotals: [Date: TimeInterval]

    var body: some View {
        let maxDay = dailyTotals.values.max() ?? 1

        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 18) {
                ForEach(months, id: \.self) { month in
                    MonthGrid(month: month, dailyTotals: dailyTotals, maxDay: maxDay)
                }
            }

            HStack(spacing: 4) {
                Text("Less")
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HeatmapStyle.fill(level: level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct MonthGrid: View {
    let month: Date
    let dailyTotals: [Date: TimeInterval]
    let maxDay: TimeInterval

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: month)!.count
        let firstWeekday = calendar.component(.weekday, from: month)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let today = calendar.startOfDay(for: .now)

        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.month(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<(leadingBlanks + days), id: \.self) { index in
                    if index < leadingBlanks {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    } else {
                        let day = calendar.date(byAdding: .day, value: index - leadingBlanks, to: month)!
                        let level = day > today ? nil : (dailyTotals[day] ?? 0) / maxDay
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level.map { HeatmapStyle.fill(level: $0) } ?? Color.primary.opacity(0.02))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
}

private enum HeatmapStyle {
    /// Monochrome so it reads well in light and dark mode.
    static func fill(level: Double) -> Color {
        level <= 0 ? Color.primary.opacity(0.07) : Color.primary.opacity(0.2 + 0.75 * min(level, 1))
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
    /// Total focus per day, keyed by start of day.
    let dailyTotals: [Date: TimeInterval]
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
        var byDay: [Date: TimeInterval] = [:]
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
            byDay[day, default: 0] += session.duration

            let barKey = "\(day.timeIntervalSince1970)-\(key)"
            byBar[barKey] = Bar(date: day, subjectKey: key, duration: (byBar[barKey]?.duration ?? 0) + session.duration)
        }
        subjects = bySubject.values.sorted { $0.duration > $1.duration }
        bars = Array(byBar.values)
        dailyTotals = byDay
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
