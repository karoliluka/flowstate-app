import Foundation

/// Everyday and interesting things to compare focus time with ("That's like 4.2 feature films").
struct FocusComparison: Identifiable {
    let id: String
    let icon: String
    let name: String
    let detail: String
    let duration: TimeInterval
}

enum FocusComparisons {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600

    // Durations are approximate and rounded for fun, not precision.
    static let catalog: [FocusComparison] = [
        .init(id: "sunlight", icon: "sun.max", name: "trips of sunlight to Earth", detail: "8 min 20 s each", duration: 500),
        .init(id: "pomodoro", icon: "timer", name: "Pomodoros", detail: "25 min each", duration: 25 * minute),
        .init(id: "football", icon: "soccerball", name: "football matches", detail: "90 min each", duration: 90 * minute),
        .init(id: "iss", icon: "globe.europe.africa", name: "laps of Earth by the ISS", detail: "about 92 min each", duration: 92 * minute),
        .init(id: "film", icon: "film", name: "feature films", detail: "about 2 h each", duration: 2 * hour),
        .init(id: "shinkansen", icon: "tram", name: "bullet trains, Tokyo to Osaka", detail: "about 2 h 20 min each", duration: 140 * minute),
        .init(id: "marathon", icon: "figure.run", name: "marathons at an average pace", detail: "about 4 h 30 min each", duration: 4.5 * hour),
        .init(id: "flight", icon: "airplane", name: "flights, London to New York", detail: "about 8 h each", duration: 8 * hour),
        .init(id: "lotr", icon: "mountain.2", name: "Lord of the Rings extended trilogies", detail: "about 11 h 30 min each", duration: 11.5 * hour),
        .init(id: "potter", icon: "wand.and.stars", name: "Harry Potter movie marathons", detail: "all 8 films, about 20 h", duration: 19.66 * hour),
        .init(id: "earth", icon: "globe", name: "spins of the Earth", detail: "24 h each", duration: 24 * hour),
        .init(id: "apollo", icon: "moon.stars", name: "Apollo 11 trips to the Moon", detail: "about 76 h each", duration: 76 * hour),
        .init(id: "transsib", icon: "train.side.front.car", name: "rides on the Trans-Siberian Railway", detail: "about a week each", duration: 7 * 24 * hour),
    ]

    /// Focus-hour goals, ending with the 10,000-hour rule for mastering a skill.
    static let milestoneHours: [Double] = [1, 10, 20, 50, 100, 200, 500, 1000, 5000, 10_000]

    /// The biggest few things that fit into `total` at least once.
    static func matches(for total: TimeInterval, limit: Int = 5) -> [(comparison: FocusComparison, count: Double)] {
        catalog
            .map { ($0, total / $0.duration) }
            .filter { $0.1 >= 1 }
            .suffix(limit)
            .reversed()
    }

    /// "1", "4.2", "37"
    static func formatCount(_ count: Double) -> String {
        if count >= 10 { return String(Int(count)) }
        let rounded = (count * 10).rounded(.down) / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
