import SwiftUI
import UIKit

/// Muted preset colors offered when creating a subject. Any other color can be picked too.
enum SubjectPalette {
    static let hexes: [String] = [
        "5C789E", // slate blue
        "6B9478", // sage
        "C78C5C", // clay
        "AB6B78", // rose
        "8C7AAD", // lavender
        "CCB366", // ochre
        "6699A6", // teal
    ]

    static func hex(at index: Int) -> String {
        hexes[abs(index) % hexes.count]
    }
}

extension Color {
    /// Creates a color from a "RRGGBB" hex string.
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "RRGGBB"
    var hex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", component(red), component(green), component(blue))
    }
}

extension Subject {
    var color: Color { Color(hex: colorHex) }
}

extension Optional where Wrapped == Subject {
    var displayName: String { self?.name ?? "No subject" }
    var displayColor: Color { self?.color ?? .secondary }
}
