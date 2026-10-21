import SwiftUI

/// Picks how long focus and break phases last.
struct PomodoroSettingsView: View {
    @Binding var focusMinutes: Int
    @Binding var breakMinutes: Int
    @Environment(\.dismiss) private var dismiss

    private var footnote: String {
        let unlock = ScreenTime.isAvailable ? " Apps unlock during breaks and lock again when focus starts." : ""
        return "Focus and breaks repeat until you end the session.\(unlock) Only focus time counts toward your stats and earned time."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(PomodoroConfig.presets, id: \.focusMinutes) { preset in
                        let isSelected = preset.focusMinutes == focusMinutes && preset.breakMinutes == breakMinutes
                        Button {
                            focusMinutes = preset.focusMinutes
                            breakMinutes = preset.breakMinutes
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(preset.focusMinutes) / \(preset.breakMinutes)")
                                    .font(.headline)
                                    .monospacedDigit()
                                Text("min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? Color.primary.opacity(0.1) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(isSelected ? 0.4 : 0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 0) {
                    wheel("Focus", selection: $focusMinutes, values: Array(stride(from: 5, through: 120, by: 5)))
                    wheel("Break", selection: $breakMinutes, values: Array(1...30))
                }

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func wheel(_ title: String, selection: Binding<Int>, values: [Int]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity)
    }
}
