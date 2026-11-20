import SwiftUI
import UIKit

struct ActiveSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The screen grows out of the Start button as a circle, and shrinks back into it on Done.
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let summary = session.summary {
                SessionSummaryView(summary: summary, onDone: close)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                RunningSessionView(blockingStatus: blockingStatus)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(Motion.gentle, value: session.summary == nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .mask {
            CircleReveal(progress: reduceMotion || revealed ? 1 : 0)
                .ignoresSafeArea()
        }
        .opacity(reduceMotion && !revealed ? 0 : 1)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.9)) {
                revealed = true
            }
        }
    }

    private var blockingStatus: String {
        if !ScreenTime.isAvailable { return "Preview build · apps aren't blocked" }
        if !blocking.isAuthorized { return "Apps aren't blocked. Allow Screen Time access first" }
        return "Distracting apps are blocked"
    }

    /// Shrinks back toward the Start button, then closes without the standard slide.
    private func close() {
        withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.45, dampingFraction: 1)) {
            revealed = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { session.dismissSummary() }
        }
    }
}

/// A circle centered on the Start button that grows until it covers the whole screen.
private struct CircleReveal: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Where the Start button sits, just above the tab bar.
        let origin = CGPoint(x: rect.midX, y: rect.maxY - 130)
        let farthest = hypot(max(origin.x, rect.width - origin.x), max(origin.y - rect.minY, rect.maxY - origin.y))
        let radius = max(0, farthest * progress)
        return Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
    }
}

private struct RunningSessionView: View {
    let blockingStatus: String

    @Environment(\.modelContext) private var context
    @Environment(SessionManager.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Elements arrive one after another (pose to pose): subject, then timer, then the end button.
    @State private var arrived = false

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
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived ? 0 : -12)
            .animation(Motion.bouncy.delay(0.15), value: arrived)

            Spacer()

            if let startedAt = session.startedAt {
                ZStack {
                    // Staging: a slow, soft glow in the subject's color is the only thing moving
                    // besides the seconds, so the eye rests on the timer.
                    BreathingGlow(color: subject.displayColor)

                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(spacing: 0) {
                            StopwatchDisplay(elapsed: timeline.date.timeIntervalSince(startedAt))
                            Text(blockingStatus)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.top, 8)
                        }
                    }
                }
                .scaleEffect(arrived || reduceMotion ? 1 : 0.9)
                .opacity(arrived ? 1 : 0)
                .animation(Motion.bouncy.delay(0.22), value: arrived)
            }

            Spacer()

            HoldToEndButton {
                session.end(in: context)
            }
            .padding(.bottom, 40)
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 30)
            .animation(Motion.bouncy.delay(0.32), value: arrived)
        }
        .onAppear { arrived = true }
    }
}

/// A soft light behind the timer that slowly swells and fades, like breathing.
private struct BreathingGlow: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.32), color.opacity(0)], center: .center, startRadius: 0, endRadius: 190))
            .frame(width: 380, height: 380)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { glow, inhale in
                glow
                    .scaleEffect(inhale ? 1.12 : 0.88)
                    .opacity(inhale ? 1 : 0.55)
            } animation: { _ in
                .easeInOut(duration: 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct StopwatchDisplay: View {
    let elapsed: TimeInterval

    var body: some View {
        Text(elapsed.clockFormatted)
            .font(.system(size: 76, weight: .thin, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .animation(Motion.snappy, value: Int(elapsed))
    }
}

/// Shown right after a session ends. It plays out one beat at a time (pose to pose):
/// the result, the time counting up, any trophy, the numbers, then Done.
private struct SessionSummaryView: View {
    let summary: SessionSummary
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var countedDuration: TimeInterval = 0

    private var hasCelebration: Bool {
        summary.milestoneHours != nil || summary.personalBest
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Group {
                    if summary.saved {
                        Image(systemName: "checkmark.circle")
                            .symbolEffect(.bounce.up, value: beat >= 1)
                    } else {
                        // A shake, like a head saying "no".
                        Image(systemName: "xmark.circle")
                            .keyframeAnimator(initialValue: 0.0, trigger: beat >= 1) { content, x in
                                content.offset(x: x)
                            } keyframes: { _ in
                                KeyframeTrack {
                                    CubicKeyframe(-8, duration: 0.07)
                                    CubicKeyframe(7, duration: 0.09)
                                    CubicKeyframe(-5, duration: 0.09)
                                    CubicKeyframe(3, duration: 0.08)
                                    SpringKeyframe(0, duration: 0.2)
                                }
                            }
                    }
                }
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
                .appear(beat >= 1)

                Text(summary.saved ? "Session complete" : "Too short to count")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .appear(beat >= 1)

                CountingDuration(value: countedDuration)
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .appear(beat >= 2)

                HStack(spacing: 8) {
                    Circle().fill(summary.subject.displayColor).frame(width: 8, height: 8)
                    Text(summary.subject.displayName)
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .appear(beat >= 2)
            }

            if hasCelebration {
                VStack(spacing: 8) {
                    if beat >= 3 {
                        if let hours = summary.milestoneHours {
                            CelebrationBadge(symbol: "trophy.fill", text: "Milestone: \(Int(hours).formatted()) hours of focus", fromLeft: true)
                        }
                        if summary.personalBest {
                            CelebrationBadge(symbol: "medal.fill", text: "Personal best: your longest session", fromLeft: false)
                        }
                    }
                }
                .frame(minHeight: 44)
                .padding(.top, 24)
            }

            VStack(spacing: 0) {
                if summary.saved {
                    row("Focused today", value: summary.focusedToday.focusFormatted, index: 0)
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
            .appear(beat >= 4)

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 32)
                .appear(beat >= 5)
        }
        .sensoryFeedback(.success, trigger: beat == 3 && hasCelebration) { _, now in now }
        .sensoryFeedback(.warning, trigger: beat == 1 && !summary.saved) { _, now in now }
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            countedDuration = summary.duration
            beat = 5
            return
        }
        let beats: [(beat: Int, pause: Double)] = [(1, 0.1), (2, 0.25), (3, hasCelebration ? 0.75 : 0.5), (4, hasCelebration ? 0.5 : 0.15), (5, 0.2)]
        for (next, pause) in beats {
            try? await Task.sleep(for: .seconds(pause))
            withAnimation(Motion.bouncy) { beat = next }
            if next == 2 {
                // Counts up fast and eases into the final number (slow out).
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9)) { countedDuration = summary.duration }
            }
        }
    }

    private func row(_ title: String, value: String, note: String? = nil, index: Int) -> some View {
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
        .opacity(beat >= 4 ? 1 : 0)
        .offset(x: beat >= 4 || reduceMotion ? 0 : 24)
        .animation(Motion.bouncy.delay(Double(index) * 0.07), value: beat >= 4)
    }
}

/// The duration, animatable so it counts up from zero.
private struct CountingDuration: View, Animatable {
    var value: TimeInterval

    var animatableData: TimeInterval {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(value.focusFormatted)
    }
}

private extension View {
    /// Fades and rises into place when `shown` turns true.
    func appear(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
    }
}

/// A gold trophy or medal moment. It flies in on an arc, stretching as it travels and squashing
/// as it lands, while the trophy spins around once in 3D.
private struct CelebrationBadge: View {
    static let gold = Color(red: 1, green: 0.78, blue: 0.2)

    let symbol: String
    let text: String
    /// Which side it flies in from.
    let fromLeft: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pose {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var opacity: Double = 1
        var spin: Double = 0
    }

    var body: some View {
        if reduceMotion {
            badge(spin: 0)
        } else {
            badge(spin: 0)
                .hidden()
                .overlay {
                    // The x and y tracks use different curves, so the path bends into an arc.
                    Color.clear.keyframeAnimator(initialValue: Pose(), repeating: false) { _, pose in
                        badge(spin: pose.spin)
                            .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                            .offset(x: pose.x, y: pose.y)
                            .opacity(pose.opacity)
                            .fixedSize()
                    } keyframes: { _ in
                        KeyframeTrack(\.x) {
                            MoveKeyframe(fromLeft ? -120 : 120)
                            CubicKeyframe(0, duration: 0.55)
                        }
                        KeyframeTrack(\.y) {
                            MoveKeyframe(60)
                            CubicKeyframe(-22, duration: 0.33)
                            SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                        }
                        KeyframeTrack(\.scaleY) {
                            MoveKeyframe(0.3)
                            CubicKeyframe(1.15, duration: 0.33)
                            CubicKeyframe(0.85, duration: 0.12)
                            SpringKeyframe(1, duration: 0.35)
                        }
                        KeyframeTrack(\.scaleX) {
                            MoveKeyframe(0.3)
                            CubicKeyframe(0.9, duration: 0.33)
                            CubicKeyframe(1.12, duration: 0.12)
                            SpringKeyframe(1, duration: 0.35)
                        }
                        KeyframeTrack(\.opacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(1, duration: 0.18)
                        }
                        KeyframeTrack(\.spin) {
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: 0.3)
                            CubicKeyframe(360, duration: 0.9)
                        }
                    }
                }
        }
    }

    private func badge(spin: Double) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Self.gold)
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Self.gold.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Self.gold.opacity(0.35)))
    }
}

/// Ending a session takes a deliberate hold, so quitting on impulse is harder.
/// Holding winds the button up (it squeezes smaller as the ring fills, and the phone taps faster
/// and harder). Letting go early springs it back; finishing pops it.
private struct HoldToEndButton: View {
    let action: () -> Void

    private let holdDuration = 1.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .stroke(.white, style: StrokeStyle(lineWidth: 3 + 2 * progress, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .scaleEffect(reduceMotion ? 1 : 1 - 0.25 * progress)
            }
            .frame(width: 76, height: 76)
            .scaleEffect(reduceMotion ? 1 : (completed ? 1.25 : 1 - 0.1 * progress))
            .opacity(completed ? 0 : 1)
            // A generous target (Fitts's law): the whole area around the ring counts.
            .padding(16)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
                withAnimation(Motion.bouncy) { completed = true }
                action()
            } onPressingChanged: { pressing in
                // Slow in while winding up; letting go springs back with a wobble.
                withAnimation(pressing ? .easeIn(duration: holdDuration) : Motion.release) {
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
