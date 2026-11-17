import SwiftUI

/// One set of timings for the whole app, so everything moves like the same character.
///
/// Springs give slow-in/slow-out for free. Presses answer within a frame or two, well inside
/// the Doherty threshold (~400 ms), and releases overshoot a little before settling (follow-through).
enum Motion {
    /// Taps, toggles and selections: quick and settled.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Things arriving or celebrating: overshoot, then settle.
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.62)
    /// Whole-screen changes: slow in, slow out.
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    /// Pressing down: the anticipating squash.
    static let press = Animation.spring(response: 0.16, dampingFraction: 0.9)
    /// Letting go: stretches back past its size and settles.
    static let release = Animation.spring(response: 0.36, dampingFraction: 0.48)
}

/// Squashes when pressed (wider and flatter, like something soft being pushed), then springs
/// back past its size and settles when released. A light tap confirms the press immediately.
struct SquishButtonStyle: ButtonStyle {
    /// Width and height while pressed.
    var squash = CGSize(width: 1.04, height: 0.9)
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SquishEffect(isPressed: configuration.isPressed, squash: squash, haptic: haptic))
    }
}

/// The squash-and-stretch press, for button styles that draw their own look.
struct SquishEffect: ViewModifier {
    let isPressed: Bool
    var squash = CGSize(width: 1.04, height: 0.9)
    var haptic = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let pressed = isPressed && isEnabled
        content
            .scaleEffect(
                x: pressed ? (reduceMotion ? 1 : squash.width) : 1,
                y: pressed ? (reduceMotion ? 1 : squash.height) : 1
            )
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(pressed ? Motion.press : (reduceMotion ? .easeOut(duration: 0.15) : Motion.release), value: pressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: pressed) { _, isPressed in haptic && isPressed }
    }
}

extension View {
    /// Grows the tappable area to at least Apple's 44 × 44 pt without changing how it looks (Fitts's law).
    func hitTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}
