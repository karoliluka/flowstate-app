import SwiftUI

/// One group: who's focusing right now, this week's leaderboard, inviting and leaving.
struct GroupDetailView: View {
    let group: StudyGroup
    let onLeave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var members: [MemberProfile] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var selected: MemberProfile?
    @State private var confirmingLeave = false

    private var me: UUID? { Backend.client.auth.currentUser?.id }

    /// Most focus this week first; ties broken by name so the order doesn't jump around.
    private var leaderboard: [MemberProfile] {
        members.sorted {
            let (a, b) = ($0.secondsThisWeek(), $1.secondsThisWeek())
            return a != b ? a > b : $0.displayName < $1.displayName
        }
    }

    private var focusingNow: [MemberProfile] {
        members.filter { $0.isActive() }.sorted { ($0.activeSince ?? .now) < ($1.activeSince ?? .now) }
    }

    var body: some View {
        List {
            if !focusingNow.isEmpty {
                Section("Focusing now") {
                    ForEach(focusingNow) { member in
                        Button { selected = member } label: { activeRow(member) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Section {
                if members.isEmpty && loaded {
                    Text(failed ? "Couldn't load the group. Pull down to try again." : "No one here yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, member in
                    Button { selected = member } label: { leaderboardRow(rank: index + 1, member: member) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("This week")
            } footer: {
                Text("Monday to Sunday. Resets every Monday.")
            }

            Section {
                ShareLink(item: InviteLink.shareMessage(groupName: group.name, code: group.inviteCode)) {
                    Label("Invite people", systemImage: "square.and.arrow.up")
                }
                LabeledContent("Invite code") {
                    Text(group.inviteCode)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Anyone with the link or code can join.")
            }

            Section {
                Button("Leave group", role: .destructive) { confirmingLeave = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if !loaded { ProgressView() }
        }
        .refreshable { await load() }
        .task {
            // Keeps "focusing now" fresh while the screen is open.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .animation(reduceMotion ? nil : Motion.snappy, value: members)
        .sheet(item: $selected) { member in
            MemberProfileView(member: member, isMe: member.id == me)
        }
        .confirmationDialog("Leave \(group.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
        } message: {
            Text("You can join again with an invite.")
        }
    }

    private func activeRow(_ member: MemberProfile) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(username: member.displayName, size: 36)
                LiveDot()
            }
            Text(member.displayName)
            Spacer()
            if let since = member.activeSince {
                // Counts up by itself, like the session timer.
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.displayName), focusing now")
    }

    private func leaderboardRow(rank: Int, member: MemberProfile) -> some View {
        let seconds = member.secondsThisWeek()
        return HStack(spacing: 12) {
            Group {
                if rank == 1 && seconds > 0 {
                    Image(systemName: "crown.fill").foregroundStyle(CelebrationGold.color)
                } else {
                    Text("\(rank)").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .frame(width: 24)

            Avatar(username: member.displayName, size: 36)
            Text(member.displayName + (member.id == me ? " (you)" : ""))
                .fontWeight(member.id == me ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            Text(seconds.focusFormatted)
                .monospacedDigit()
                .foregroundStyle(seconds > 0 ? .primary : .secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            members = try await GroupService.members(of: group)
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    private func leave() async {
        do {
            try await GroupService.leave(group)
            onLeave()
            dismiss()
        } catch {
            failed = true
        }
    }
}

/// A green dot that gently pulses: this person is focusing right now.
private struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { dot, on in
                dot.scaleEffect(on ? 1.15 : 0.9)
            } animation: { _ in .easeInOut(duration: 1.2) }
    }
}

enum CelebrationGold {
    static let color = Color(red: 1, green: 0.78, blue: 0.2)
}

/// A group mate: their name, total focus as a badge under their initial, and this week.
struct MemberProfileView: View {
    let member: MemberProfile
    let isMe: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Avatar(username: member.displayName, size: 88)
                    .padding(.top, 24)
                FocusBadge(seconds: TimeInterval(member.totalSeconds))
                Text(member.displayName + (isMe ? " (you)" : ""))
                    .font(.title2.weight(.semibold))

                if member.isActive(), let since = member.activeSince {
                    Label {
                        Text("Focusing now · ") + Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    } icon: {
                        Circle().fill(.green).frame(width: 8, height: 8)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    tile("This week", member.secondsThisWeek().focusFormatted)
                    tile("All time", TimeInterval(member.totalSeconds).focusFormatted)
                }
                .padding(.top, 12)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }
}

/// Total focus time as a small badge, shown under someone's initial on their profile.
struct FocusBadge: View {
    let seconds: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "stopwatch.fill")
            Text(seconds.focusFormatted + " focused")
        }
            .font(.caption.weight(.semibold))
            .fixedSize()
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("\(seconds.focusFormatted) of focus in total")
    }
}
