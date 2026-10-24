import SwiftUI
import SwiftData
import Charts

struct SubjectDetailView: View {
    let subject: Subject

    @Environment(\.modelContext) private var context
    @State private var showingEditor = false

    private var sessions: [FocusSession] {
        subject.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        let sessions = sessions
        let total = subject.totalDuration

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "This week", value: subject.thisWeekDuration.focusFormatted)
                    StatTile(title: "Total", value: total.focusFormatted)
                    StatTile(title: "Sessions", value: "\(sessions.count)")
                    StatTile(title: "Average session", value: (sessions.isEmpty ? 0 : total / Double(sessions.count)).focusFormatted)
                }

                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Last 8 weeks").font(.headline)
                        weeklyChart
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sessions").font(.headline)
                        ForEach(sessions.prefix(30)) { session in
                            SessionRow(session: session)
                                .contextMenu {
                                    Button("Delete session", systemImage: "trash", role: .destructive) {
                                        context.delete(session)
                                    }
                                }
                            Divider()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "timer",
                        description: Text("Pick \(subject.name) on the Focus tab and start a session.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle(subject.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SubjectEditor(subject: subject)
        }
    }

    private var weeklyChart: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        let weeks = (0..<8).reversed().map { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)! }
        var totals = Dictionary(uniqueKeysWithValues: weeks.map { ($0, 0.0) })
        for session in subject.sessions {
            let week = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)!.start
            if totals[week] != nil { totals[week]! += session.duration }
        }

        return Chart {
            ForEach(weeks, id: \.self) { week in
                BarMark(
                    x: .value("Week", week, unit: .weekOfYear),
                    y: .value("Hours", totals[week]! / 3600)
                )
                .foregroundStyle(subject.color)
                .cornerRadius(4)
            }
        }
        // Cover the whole current week, so the stride below also has a mark after it
        // and the current week's centered label isn't dropped.
        .chartXScale(domain: weeks.first!...calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek)!)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours.formatted())h") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .frame(height: 180)
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt, format: .dateTime.weekday(.wide).day().month())
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) – \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.duration.focusFormatted)
                .monospacedDigit()
        }
        .font(.subheadline)
        .contentShape(Rectangle())
    }
}
