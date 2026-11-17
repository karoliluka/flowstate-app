import SwiftUI

/// The logo drawing itself on launch, before fading into the app.
struct IntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var finished = false

    var body: some View {
        LogoScreen(progress: progress)
        // Tapping skips straight to the app, for when you just want to start.
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("flowstate. Tap to skip")
        .task {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeInOut(duration: 1.5)) { progress = 1 }
            }
            // Draw 1.5 s, hold 0.4 s, then 0.9 s fading out over the home screen: 2.8 s in all.
            try? await Task.sleep(for: .seconds(1.9))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// The logo on the icon's dark background. Also covers the app in the app switcher.
struct LogoScreen: View {
    var progress: CGFloat = 1

    private let width: CGFloat = 170

    var body: some View {
        ZStack {
            Color.introBackground.ignoresSafeArea()
            LogoWave()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: width * LogoWave.thickness, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: width * LogoWave.aspectRatio)
        }
    }
}

extension Color {
    /// The icon's background, also used for the launch screen so there's no flash before the intro.
    static let introBackground = Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255)
}
