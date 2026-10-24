import SwiftUI
import UIKit

struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(EarnedTimeManager.self) private var earned

    var body: some View {
        ZStack {
            if let summary = session.summary {
                SessionSummaryView(summary: summary, onDone: session.dismissSummary)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                running
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: session.summary == nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var running: some View {
        let subject = session.subject(in: context)

        return VStack(spacing: 0) {
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

/// Shown right after a session ends: how long, what it earned, and today's total.
private struct SessionSummaryView: View {
    let summary: SessionSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: summary.saved ? "checkmark.circle" : "xmark.circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(summary.saved ? "Session complete" : "Too short to count")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                Text(summary.duration.focusFormatted)
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Circle().fill(summary.subject.displayColor).frame(width: 8, height: 8)
                    Text(summary.subject.displayName)
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            }

            if summary.milestoneHours != nil || summary.personalBest {
                VStack(spacing: 8) {
                    if let hours = summary.milestoneHours {
                        CelebrationBadge(symbol: "trophy.fill", text: "Milestone: \(Int(hours).formatted()) hours of focus")
                    }
                    if summary.personalBest {
                        CelebrationBadge(symbol: "medal.fill", text: "Personal best: your longest session")
                    }
                }
                .padding(.top, 24)
            }

            VStack(spacing: 0) {
                if summary.saved {
                    if summary.earnedMinutes * 60 < 1 && summary.balanceFull {
                        row("Scrolling earned", value: "Full", note: "Spend some earned time to keep earning")
                    } else {
                        row("Scrolling earned", value: "+\((summary.earnedMinutes * 60).focusFormatted)",
                            note: summary.balanceFull ? "Your balance is now full" : nil)
                    }
                    if summary.deepFocus {
                        Divider().overlay(.white.opacity(0.1))
                        row("Deep focus bonus", value: "1.5×")
                    }
                    Divider().overlay(.white.opacity(0.1))
                    row("Focused today", value: summary.focusedToday.focusFormatted)
                } else {
                    Text("Sessions shorter than \(Int(SessionManager.minimumDuration)) seconds aren't saved.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(16)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.07)))
            .padding(.horizontal, 24)
            .padding(.top, 36)

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
    }

    private func row(_ title: String, value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(16)
    }
}

/// A gold trophy or medal moment on the session summary.
private struct CelebrationBadge: View {
    static let gold = Color(red: 1, green: 0.78, blue: 0.2)

    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Self.gold)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Self.gold.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Self.gold.opacity(0.35)))
    }
}

/// Ending a session takes a deliberate hold, so quitting on impulse is harder.
/// While held, the phone taps faster and harder until the session ends.
private struct HoldToEndButton: View {
    let action: () -> Void

    private let holdDuration = 1.5
    @State private var progress: CGFloat = 0
    @State private var completed = false
    @State private var buildUp: Task<Void, Never>?

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
                buildUp?.cancel()
                buildUp = pressing ? Task { await buildUpHaptics() } : nil
            }
            .sensoryFeedback(.success, trigger: completed)
            .accessibilityLabel("End session")
            .accessibilityAction { action() }

            Text("Hold to end")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// Light, slow taps at first, getting stronger and closer together toward the end of the hold.
    @MainActor
    private func buildUpHaptics() async {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        let start = Date.now
        while !Task.isCancelled {
            let progress = Date.now.timeIntervalSince(start) / holdDuration
            guard progress < 1 else { return }
            generator.impactOccurred(intensity: 0.15 + 0.85 * progress)
            try? await Task.sleep(for: .seconds(0.16 - 0.11 * progress))
        }
    }
}
