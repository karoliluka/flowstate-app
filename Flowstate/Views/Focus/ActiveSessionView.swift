import SwiftUI

struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(EarnedTimeManager.self) private var earned

    var body: some View {
        let subject = session.subject(in: context)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(subject.displayColor).frame(width: 8, height: 8)
                Text(subject.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 24)

            Spacer()

            if let startedAt = session.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        StopwatchDisplay(elapsed: context.date.timeIntervalSince(startedAt))
                        Text(blockingStatus)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 8)
                    }
                }
            }

            Spacer()

            HoldToEndButton {
                session.end(in: context)
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var blockingStatus: String {
        if !ScreenTime.isAvailable { return "Preview build · apps aren't blocked" }
        if !blocking.isAuthorized { return "Apps aren't blocked. Allow Screen Time access first" }
        return "Distracting apps are blocked"
    }
}

private struct StopwatchDisplay: View {
    @Environment(EarnedTimeManager.self) private var earned
    let elapsed: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            Text(elapsed.clockFormatted)
                .font(.system(size: 76, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("+\((earned.earned(for: elapsed) * 60).focusFormatted) of scrolling earned")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
            if elapsed >= EarnedTimeManager.deepFocusThreshold {
                Text("Deep focus · 1.5× bonus")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Ending a session takes a deliberate hold, so quitting on impulse is harder.
private struct HoldToEndButton: View {
    let action: () -> Void

    private let holdDuration = 1.5
    @State private var progress: CGFloat = 0
    @State private var completed = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
                completed.toggle()
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.2)) {
                    progress = pressing ? 1 : 0
                }
            }
            .sensoryFeedback(.success, trigger: completed)
            .accessibilityLabel("End session")
            .accessibilityAction { action() }

            Text("Hold to end")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
