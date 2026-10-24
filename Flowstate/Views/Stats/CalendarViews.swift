import SwiftUI
import SwiftData
import Charts

/// A month in the year calendar, opened with a zoom.
struct CalendarMonth: Hashable {
    let start: Date
}

/// A day in a month calendar, opened with a zoom.
struct CalendarDay: Hashable {
    let start: Date
}

/// How much was focused on one day, and the color of the subject focused on most.
struct DayFocus {
    let total: TimeInterval
    let color: Color

    static func byDay(_ sessions: [FocusSession], calendar: Calendar = .current) -> [Date: DayFocus] {
        var perDay: [Date: [String: (duration: TimeInterval, color: Color)]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            let key = session.subject?.uuid.uuidString ?? "none"
            let duration = (perDay[day]?[key]?.duration ?? 0) + session.duration
            perDay[day, default: [:]][key] = (duration, session.subject.displayColor)
        }
        return perDay.mapValues { subjects in
            let top = subjects.values.max { $0.duration < $1.duration }!
            return DayFocus(total: subjects.values.reduce(0) { $0 + $1.duration }, color: top.color)
        }
    }
}

enum HeatmapStyle {
    /// The top subject's color, stronger the longer the day's focus.
    static func fill(_ focus: DayFocus?, maxDay: TimeInterval) -> Color {
        guard let focus, focus.total > 0 else { return Color.primary.opacity(0.07) }
        return focus.color.opacity(0.25 + 0.75 * min(1, focus.total / max(maxDay, 1)))
    }

    static let future = Color.primary.opacity(0.02)
}

extension Calendar {
    /// Weekday initials starting from the locale's first weekday.
    var orderedWeekdayInitials: [String] {
        let symbols = veryShortStandaloneWeekdaySymbols
        return Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
    }

    /// Empty cells before the 1st, so it lands under the right weekday.
    func leadingBlanks(forMonthStarting month: Date) -> Int {
        (component(.weekday, from: month) - firstWeekday + 7) % 7
    }
}

// MARK: - Zoom transitions

extension View {
    /// Where a zoom transition starts. Needs iOS 18; earlier versions use the normal push.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Zooms this screen in from the matching `zoomSource`.
    @ViewBuilder
    func zoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Month

/// One month as a large calendar, with its totals. Days with focus open their own chart.
struct MonthDetailView: View {
    let month: CalendarMonth
    let namespace: Namespace.ID

    @Query private var sessions: [FocusSession]

    init(month: CalendarMonth, namespace: Namespace.ID) {
        self.month = month
        self.namespace = namespace
        let start = month.start
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        _sessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= start && $0.startedAt < end })
    }

    var body: some View {
        let calendar = Calendar.current
        let days = DayFocus.byDay(sessions, calendar: calendar)
        let maxDay = days.values.map(\.total).max() ?? 1
        let total = sessions.reduce(0) { $0 + $1.duration }
        let bestDay = days.max { $0.value.total < $1.value.total }

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Focused", value: total.focusFormatted)
                    StatTile(title: "Days focused", value: "\(days.count)")
                    StatTile(title: "Sessions", value: "\(sessions.count)")
                    StatTile(title: "Best day", value: bestDay.map { $0.value.total.focusFormatted } ?? "–")
                }

                calendarGrid(days: days, maxDay: maxDay, calendar: calendar)

                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("By subject").font(.headline)
                        SubjectBreakdown(sessions: sessions)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(month.start.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.large)
    }

    private func calendarGrid(days: [Date: DayFocus], maxDay: TimeInterval, calendar: Calendar) -> some View {
        let dayCount = calendar.range(of: .day, in: .month, for: month.start)!.count
        let blanks = calendar.leadingBlanks(forMonthStarting: month.start)
        let today = calendar.startOfDay(for: .now)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(calendar.orderedWeekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<(blanks + dayCount), id: \.self) { index in
                    if index < blanks {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    } else {
                        let date = calendar.date(byAdding: .day, value: index - blanks, to: month.start)!
                        dayCell(date: date, focus: days[date], maxDay: maxDay, isFuture: date > today, calendar: calendar)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date, focus: DayFocus?, maxDay: TimeInterval, isFuture: Bool, calendar: Calendar) -> some View {
        let cell = RoundedRectangle(cornerRadius: 8)
            .fill(isFuture ? HeatmapStyle.future : HeatmapStyle.fill(focus, maxDay: maxDay))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isFuture ? .tertiary : .primary)
            }

        if focus != nil {
            let day = CalendarDay(start: date)
            NavigationLink(value: day) { cell }
                .buttonStyle(.plain)
                .zoomSource(id: day, in: namespace)
                .accessibilityLabel(Text("\(date.formatted(date: .complete, time: .omitted)), \(focus!.total.focusFormatted) focused"))
        } else {
            cell
        }
    }
}

// MARK: - Day

/// One day hour by hour, stacked by subject, with its sessions.
struct DayDetailView: View {
    let day: CalendarDay

    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]

    init(day: CalendarDay) {
        self.day = day
        let start = day.start
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        _sessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= start && $0.startedAt < end }, sort: \.startedAt)
    }

    private struct HourBar: Identifiable {
        let hour: Date
        let subjectKey: String
        let duration: TimeInterval
        var id: String { "\(hour.timeIntervalSince1970)-\(subjectKey)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day.start)!
        let total = sessions.reduce(0) { $0 + $1.duration }
        let bars = hourBars(dayEnd: dayEnd, calendar: calendar)
        let subjects = SubjectBreakdown.totals(sessions)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Focused", value: total.focusFormatted)
                    StatTile(title: "Sessions", value: "\(sessions.count)")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Through the day").font(.headline)
                    Chart(bars) { bar in
                        BarMark(
                            x: .value("Hour", bar.hour, unit: .hour),
                            y: .value("Minutes", bar.duration / 60)
                        )
                        .foregroundStyle(by: .value("Subject", bar.subjectKey))
                        .cornerRadius(2)
                    }
                    .chartForegroundStyleScale(domain: subjects.map(\.id), range: subjects.map(\.color))
                    .chartLegend(.hidden)
                    .chartXScale(domain: day.start...dayEnd)
                    .chartYScale(domain: 0...60)
                    .chartYAxis {
                        AxisMarks(values: [0, 30, 60]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let minutes = value.as(Int.self) { Text("\(minutes)m") }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(height: 180)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sessions").font(.headline)
                    ForEach(sessions) { session in
                        HStack {
                            Circle().fill(session.subject.displayColor).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.subject.displayName)
                                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) – \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(session.duration.focusFormatted)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        Divider()
                    }
                }
            }
            .padding()
        }
        .navigationTitle(day.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Minutes per hour and subject; sessions running across hours are split between them.
    private func hourBars(dayEnd: Date, calendar: Calendar) -> [HourBar] {
        var totals: [String: HourBar] = [:]
        for session in sessions {
            let key = session.subject?.uuid.uuidString ?? "none"
            var cursor = session.startedAt
            let end = min(session.endedAt, dayEnd)
            while cursor < end {
                let hour = calendar.dateInterval(of: .hour, for: cursor)!
                let segmentEnd = min(hour.end, end)
                let id = "\(hour.start.timeIntervalSince1970)-\(key)"
                totals[id] = HourBar(hour: hour.start, subjectKey: key, duration: (totals[id]?.duration ?? 0) + segmentEnd.timeIntervalSince(cursor))
                cursor = segmentEnd
            }
        }
        return Array(totals.values)
    }
}

// MARK: - Shared

/// Time per subject with proportional bars, most-focused first.
struct SubjectBreakdown: View {
    let sessions: [FocusSession]

    struct Total: Identifiable {
        let id: String
        let name: String
        let color: Color
        let duration: TimeInterval
    }

    static func totals(_ sessions: [FocusSession]) -> [Total] {
        var totals: [String: Total] = [:]
        for session in sessions {
            let key = session.subject?.uuid.uuidString ?? "none"
            totals[key] = Total(
                id: key,
                name: session.subject.displayName,
                color: session.subject.displayColor,
                duration: (totals[key]?.duration ?? 0) + session.duration
            )
        }
        return totals.values.sorted { $0.duration > $1.duration }
    }

    var body: some View {
        let totals = Self.totals(sessions)
        let all = max(totals.reduce(0) { $0 + $1.duration }, 1)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(totals) { subject in
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
                            .frame(width: geometry.size.width * subject.duration / all)
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
