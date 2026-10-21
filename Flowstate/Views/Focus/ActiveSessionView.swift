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
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    let isBreak = session.pomodoro?.state(elapsed: elapsed).phase == .rest
                    VStack(spacing: 0) {
                        if let pomodoro = session.pomodoro {
                            PomodoroDisplay(config: pomodoro, startedAt: startedAt, now: context.date)
                        } else {
                            StopwatchDisplay(elapsed: elapsed)
                        }
                        Text(blockingStatus(isBreak: isBreak))
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

    private func blockingStatus(isBreak: Bool) -> String {
        if !ScreenTime.isAvailable { return "Preview build · apps aren't blocked" }
        if !blocking.isAuthorized { return "Apps aren't blocked. Allow Screen Time access first" }
        if isBreak {
            return session.breakStaysBlocked ? "Apps stay blocked during this break" : "Apps are unlocked until the break ends"
        }
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

/// Counts down the current focus or break phase.
private struct PomodoroDisplay: View {
    @Environment(EarnedTimeManager.self) private var earned
    let config: PomodoroConfig
    let startedAt: Date
    let now: Date

    var body: some View {
        let state = config.state(elapsed: now.timeIntervalSince(startedAt))
        let isFocus = state.phase == .focus
        let phaseLength = isFocus ? config.focus : config.rest
        let earnedSoFar = config.focusBlocks(from: startedAt, to: now)
            .reduce(0) { $0 + earned.earned(for: $1.end.timeIntervalSince($1.start)) }

        VStack(spacing: 10) {
            Text(isFocus ? "Focus · round \(state.round)" : "Break")
                .font(.headline)
                .foregroundStyle(.white.opacity(isFocus ? 0.9 : 0.6))

            Text(state.remaining.rounded(.up).clockFormatted)
                .font(.system(size: 76, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(isFocus ? 1 : 0.7)

            // Phase progress
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(.white.opacity(isFocus ? 1 : 0.5))
                        .frame(width: geometry.size.width * (1 - state.remaining / phaseLength))
                }
            }
            .frame(width: 180, height: 4)

            Text("\(state.focused.focusFormatted) focused · +\((earnedSoFar * 60).focusFormatted) earned")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 6)

            if !isFocus {
                Text("Stand up, stretch, drink some water.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: state.phase)
        .animation(.easeInOut, value: state.phase)
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
