import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(EarnedTimeManager.self) private var earned
    @Query private var sessions: [FocusSession]

    @AppStorage(StorageKeys.username) private var username = ""
    @AppStorage(StorageKeys.appearance) private var appearance: AppearanceMode = .system
    @State private var confirmingSampleData = false
    @State private var confirmingDeleteAll = false

    private var allTime: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Avatar(username: username, size: 56)
                        TextField("Your name", text: $username)
                            .font(.title3)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("All time") {
                    LabeledContent("Focused", value: allTime.focusFormatted)
                    LabeledContent("Sessions", value: "\(sessions.count)")
                }

                Section("Milestones") {
                    MilestonesView(hours: allTime / 3600)
                        .padding(.vertical, 6)
                }

                #if DEBUG
                Section {
                    Button("Load sample data") {
                        confirmingSampleData = true
                    }
                    Button("Add 30 min earned time") {
                        earned.debugAddBalance(30)
                    }
                    Button("Delete all data", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Only visible in debug builds.")
                }
                #endif
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if DEBUG
            // These wipe real data too, and the Preview build on a phone includes them.
            .confirmationDialog("Replace all your subjects and sessions with sample data?", isPresented: $confirmingSampleData, titleVisibility: .visible) {
                Button("Replace with sample data", role: .destructive) {
                    SampleData.replaceAll(in: context)
                }
            }
            .confirmationDialog("Delete all subjects and sessions?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    SampleData.deleteAll(in: context)
                }
            } message: {
                Text("This can't be undone.")
            }
            #endif
        }
    }
}

/// The user's initial in a circle, or a person icon when no name is set.
struct Avatar: View {
    let username: String
    var size: CGFloat = 32

    var body: some View {
        let initial = username.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
        ZStack {
            Circle().fill(Color.primary.opacity(0.08))
            if let initial {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Progress toward the next focus-hour goal, plus the whole ladder up to 10,000 h.
private struct MilestonesView: View {
    let hours: Double

    var body: some View {
        let levels = FocusComparisons.milestoneHours
        let nextIndex = levels.firstIndex { hours < $0 }
        let previous = nextIndex.flatMap { $0 > 0 ? levels[$0 - 1] : nil } ?? 0

        VStack(alignment: .leading, spacing: 16) {
            if let nextIndex {
                let next = levels[nextIndex]
                let isFinal = nextIndex == levels.count - 1
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Next goal")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(isFinal ? "Master a skill" : Self.format(next))
                            .font(.headline)
                    }
                    ProgressView(value: (hours - previous) / (next - previous))
                        .tint(.primary)
                    Text("\(Self.format(hours)) of \(Self.format(next)) · \(Self.formatRemaining(next - hours)) to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Label("You've reached 10,000 hours. Skill mastered.", systemImage: "trophy.fill")
                    .font(.headline)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(levels.indices, id: \.self) { index in
                    chip(levels[index], reached: hours >= levels[index], isNext: index == nextIndex, isFinal: index == levels.count - 1)
                }
            }

            Text("10,000 hours is the classic rule for mastering a skill.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chip(_ level: Double, reached: Bool, isNext: Bool, isFinal: Bool) -> some View {
        HStack(spacing: 3) {
            if isFinal { Image(systemName: "trophy.fill").font(.caption2) }
            Text(level >= 1000 ? "\(Int(level / 1000))k" : "\(Int(level))h")
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .foregroundStyle(reached ? Color(.systemBackground) : (isNext ? .primary : .secondary))
        .background(Capsule().fill(reached ? Color.primary : .clear))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(reached ? 0 : (isNext ? 0.6 : 0.15))))
    }

    /// "45 min", "12 h", "1,250 h"
    static func format(_ hours: Double) -> String {
        hours < 1 ? "\(Int(hours * 60)) min" : "\(Int(hours).formatted()) h"
    }

    /// Rounded up, so "428 h of 500 h" says "72 h to go" and adds up.
    static func formatRemaining(_ hours: Double) -> String {
        hours < 1 ? "\(Int((hours * 60).rounded(.up))) min" : "\(Int(hours.rounded(.up)).formatted()) h"
    }
}
