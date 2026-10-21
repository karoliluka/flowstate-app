import SwiftUI

/// The logo drawing itself on launch, before fading into the app.
struct IntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        LogoScreen(progress: progress)
        .task {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeInOut(duration: 1.5)) { progress = 1 }
            }
            // Draw 1.5 s, hold 0.4 s, then 0.9 s fading out over the home screen: 2.8 s in all.
            try? await Task.sleep(for: .seconds(1.9))
            onFinish()
        }
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

/// The wave from the app icon, traced from the original artwork.
struct LogoWave: Shape {
    /// Stroke width relative to the wave's width, as in the icon.
    static let thickness: CGFloat = 0.044
    static let aspectRatio: CGFloat = 0.27

    /// Points along the wave: x from 0 to 1, y relative to the width around the middle.
    private static let points: [CGPoint] = [
        (0.000, 0.070), (0.022, 0.076), (0.044, 0.081), (0.063, 0.083), (0.085, 0.084), (0.107, 0.083),
        (0.129, 0.079), (0.150, 0.072), (0.169, 0.063), (0.191, 0.050), (0.213, 0.034), (0.235, 0.012),
        (0.254, -0.008), (0.276, -0.034), (0.298, -0.060), (0.320, -0.084), (0.342, -0.104), (0.361, -0.117),
        (0.382, -0.129), (0.404, -0.135), (0.426, -0.134), (0.448, -0.128), (0.467, -0.117), (0.489, -0.096),
        (0.511, -0.069), (0.533, -0.034), (0.552, 0.001), (0.574, 0.042), (0.596, 0.077), (0.618, 0.104),
        (0.639, 0.123), (0.658, 0.131), (0.680, 0.135), (0.702, 0.131), (0.724, 0.123), (0.746, 0.108),
        (0.765, 0.092), (0.787, 0.071), (0.809, 0.050), (0.831, 0.031), (0.850, 0.018), (0.871, 0.006),
        (0.893, -0.001), (0.915, -0.004), (0.937, -0.003), (0.956, 0.000), (0.978, 0.007), (1.000, 0.016),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    func path(in rect: CGRect) -> Path {
        let scaled = Self.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.midY + $0.y * rect.width) }
        var path = Path()
        path.move(to: scaled[0])
        // Curves through the midpoints between samples, so the line stays smooth.
        for index in 1..<scaled.count {
            let previous = scaled[index - 1]
            let midpoint = CGPoint(x: (previous.x + scaled[index].x) / 2, y: (previous.y + scaled[index].y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
        }
        path.addLine(to: scaled[scaled.count - 1])
        return path
    }
}
