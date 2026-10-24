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
        .init(id: "tiktok", icon: "play.rectangle", name: "TikToks you didn't watch", detail: "about 30 s each", duration: 30),
        .init(id: "song", icon: "music.note", name: "pop songs", detail: "about 3 min 30 s each", duration: 210),
        .init(id: "tea", icon: "cup.and.saucer", name: "cups of tea brewed", detail: "4 min each", duration: 4 * minute),
        .init(id: "sunlight", icon: "sun.max", name: "trips of sunlight to Earth", detail: "8 min 20 s each", duration: 500),
        .init(id: "mars", icon: "sparkle", name: "radio messages to Mars", detail: "about 12 min 30 s each, on average", duration: 750),
        .init(id: "nap", icon: "bed.double", name: "power naps", detail: "20 min each", duration: 20 * minute),
        .init(id: "sitcom", icon: "tv", name: "sitcom episodes", detail: "about 22 min each", duration: 22 * minute),
        .init(id: "pomodoro", icon: "timer", name: "Pomodoros", detail: "25 min each", duration: 25 * minute),
        .init(id: "beethoven", icon: "music.quarternote.3", name: "Beethoven's 9th symphonies", detail: "about 70 min each", duration: 70 * minute),
        .init(id: "football", icon: "soccerball", name: "football matches", detail: "90 min each", duration: 90 * minute),
        .init(id: "f1", icon: "flag.checkered", name: "Formula 1 races", detail: "about 1 h 30 min each", duration: 90 * minute),
        .init(id: "charge", icon: "battery.100.bolt", name: "full iPhone charges", detail: "about 1 h 45 min each", duration: 105 * minute),
        .init(id: "iss", icon: "globe.europe.africa", name: "laps of Earth by the ISS", detail: "about 92 min each", duration: 92 * minute),
        .init(id: "film", icon: "film", name: "feature films", detail: "about 2 h each", duration: 2 * hour),
        .init(id: "shinkansen", icon: "tram", name: "bullet trains, Tokyo to Osaka", detail: "about 2 h 20 min each", duration: 140 * minute),
        .init(id: "nba", icon: "basketball", name: "NBA games", detail: "about 2 h 15 min each", duration: 135 * minute),
        .init(id: "titanic", icon: "ferry", name: "Titanic movies", detail: "3 h 14 min each", duration: 194 * minute),
        .init(id: "superbowl", icon: "football", name: "Super Bowl broadcasts", detail: "about 3 h 30 min each", duration: 3.5 * hour),
        .init(id: "marathon", icon: "figure.run", name: "marathons at an average pace", detail: "about 4 h 30 min each", duration: 4.5 * hour),
        .init(id: "tour", icon: "bicycle", name: "Tour de France stages", detail: "about 4 h 30 min each", duration: 4.5 * hour),
        .init(id: "flight", icon: "airplane", name: "flights, London to New York", detail: "about 8 h each", duration: 8 * hour),
        .init(id: "hobbit", icon: "book", name: "audiobooks of The Hobbit", detail: "about 10 h each", duration: 10 * hour),
        .init(id: "ironman", icon: "figure.open.water.swim", name: "Ironman triathlons", detail: "about 12 h 30 min each, on average", duration: 12.5 * hour),
        .init(id: "lotr", icon: "mountain.2", name: "Lord of the Rings extended trilogies", detail: "about 11 h 30 min each", duration: 11.5 * hour),
        .init(id: "potter", icon: "wand.and.stars", name: "Harry Potter movie marathons", detail: "all 8 films, about 20 h", duration: 19.66 * hour),
        .init(id: "earth", icon: "globe", name: "spins of the Earth", detail: "24 h each", duration: 24 * hour),
        .init(id: "apollo", icon: "moon.stars", name: "Apollo 11 trips to the Moon", detail: "about 76 h each", duration: 76 * hour),
        .init(id: "transsib", icon: "train.side.front.car", name: "rides on the Trans-Siberian Railway", detail: "about a week each", duration: 7 * 24 * hour),
    ]

    /// Focus-hour goals, ending with the 10,000-hour rule for mastering a skill.
    static let milestoneHours: [Double] = [1, 10, 20, 50, 100, 200, 500, 1000, 5000, 10_000]

    /// A random few of the things that fit into `total` at least once, biggest first.
    /// The same `seed` always picks the same ones, so they only change when the seed does.
    static func matches(for total: TimeInterval, seed: UInt64, limit: Int = 3) -> [(comparison: FocusComparison, count: Double)] {
        var generator = SeededGenerator(seed: seed)
        return catalog
            .map { ($0, total / $0.duration) }
            .filter { $0.1 >= 1 }
            .shuffled(using: &generator)
            .prefix(limit)
            .sorted { $0.0.duration > $1.0.duration }
    }

    /// "1", "4.2", "37", "1,204"
    static func formatCount(_ count: Double) -> String {
        if count >= 10 { return Int(count).formatted() }
        let rounded = (count * 10).rounded(.down) / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

/// A small, repeatable random number generator (SplitMix64), so a seed gives the same picks every time.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
