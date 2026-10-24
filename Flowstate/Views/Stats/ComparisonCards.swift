import SwiftUI

extension EnvironmentValues {
    /// Picks which comparisons are shown. RootView changes it every time the app opens.
    @Entry var comparisonSeed: UInt64 = 0
}

/// Swipeable cards comparing focus time with everyday things, three random ones at a time.
struct ComparisonCards: View {
    let total: TimeInterval

    @Environment(\.comparisonSeed) private var seed

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(FocusComparisons.matches(for: total, seed: seed), id: \.comparison.id) { match in
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: match.comparison.icon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(FocusComparisons.formatCount(match.count) + "×")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(match.comparison.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2, reservesSpace: true)
                        Text(match.comparison.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.62 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
