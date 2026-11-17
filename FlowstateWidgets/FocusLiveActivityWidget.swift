import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FlowstateWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivityWidget()
    }
}

/// The running session on the Lock Screen and in the Dynamic Island: subject, a live timer,
/// and the next few "that's like" goals filling up as you focus.
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, goals: context.state.goals)
                .activityBackgroundTint(Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255).opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let color = Color(activityHex: attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SubjectLabel(name: attributes.subjectName, color: color)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Logo(color: .white.opacity(0.9), width: 30)
                        .padding(.trailing, 6)
                        .padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.center) {
                    ElapsedTimer(startedAt: attributes.startedAt)
                        .font(.system(size: 38, weight: .light, design: .rounded))
                        .padding(.top, 14)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GoalStrip(goals: context.state.goals, startedAt: attributes.startedAt, color: color)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Logo(color: color, width: 22)
                    .padding(.leading, 2)
            } compactTrailing: {
                ElapsedTimer(startedAt: attributes.startedAt)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Logo(color: color, width: 18)
            }
            .keylineTint(color)
        }
    }
}

private struct LockScreenView: View {
    let attributes: FocusActivityAttributes
    let goals: [FocusActivityAttributes.Goal]

    var body: some View {
        let color = Color(activityHex: attributes.colorHex)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    SubjectLabel(name: attributes.subjectName, color: color)
                    ElapsedTimer(startedAt: attributes.startedAt)
                        .font(.system(size: 40, weight: .light, design: .rounded))
                }
                Spacer(minLength: 12)
                Logo(color: .white.opacity(0.85), width: 34)
                    .padding(.top, 6)
            }
            GoalStrip(goals: goals, startedAt: attributes.startedAt, color: color)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct SubjectLabel: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.75))
    }
}

/// Counts up from the session start by itself, also while the app is closed.
private struct ElapsedTimer: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
    }
}

/// Up to three goals side by side (Miller's law: a glance, not a list), each a bar that fills
/// from the session start until that comparison is reached.
private struct GoalStrip: View {
    let goals: [FocusActivityAttributes.Goal]
    let startedAt: Date
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(goals) { goal in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: goal.icon)
                            .font(.caption2)
                            .foregroundStyle(color)
                        Text(goal.title)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    ProgressView(
                        timerInterval: startedAt...startedAt.addingTimeInterval(max(1, goal.reachedAfter)),
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .progressViewStyle(.linear)
                    .tint(color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The wave from the app icon.
private struct Logo: View {
    let color: Color
    let width: CGFloat

    var body: some View {
        LogoWave()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.6, width * LogoWave.thickness * 1.6), lineCap: .round, lineJoin: .round))
            .frame(width: width, height: width * LogoWave.aspectRatio)
    }
}

private extension Color {
    /// "RRGGBB"
    init(activityHex hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x8E8E93
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#if DEBUG
#Preview("Lock Screen", as: .content, using: FocusActivityAttributes(startedAt: .now.addingTimeInterval(-38 * 60), subjectName: "Calculus", colorHex: "0A84FF")) {
    FocusLiveActivityWidget()
} contentStates: {
    FocusActivityAttributes.ContentState(goals: [
        .init(id: "pomodoro", icon: "timer", title: "2× Pomodoros", reachedAfter: 50 * 60),
        .init(id: "film", icon: "film", title: "1× feature films", reachedAfter: 2 * 3600),
        .init(id: "flight", icon: "airplane", title: "1× flights", reachedAfter: 8 * 3600),
    ])
}
#endif
