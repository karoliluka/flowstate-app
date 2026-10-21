import SwiftUI
import FamilyControls

/// Spend earned scrolling time, pick distracting apps and the earning mode.
struct EarnedTimeView: View {
    @Environment(EarnedTimeManager.self) private var earned
    @Environment(BlockingManager.self) private var blocking
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false
    /// The picker edits a copy; it's handed to `requestDistracting` when the picker closes.
    @State private var draft = FamilyActivitySelection()
    @State private var draftStart = FamilyActivitySelection()
    /// An easier mode waiting for the user to confirm the cooldown.
    @State private var confirmingMode: EarnMode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BalanceRing(balance: earned.balance, cap: earned.mode.cap)
                        .padding(.vertical, 12)

                    if !ScreenTime.isAvailable {
                        Card {
                            Text("App blocking is off in this preview build. Your balance still grows as you focus.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if !blocking.isAuthorized {
                        Card {
                            Text("Allow Screen Time access to block distracting apps.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Allow") {
                                Task {
                                    await blocking.requestAuthorization()
                                    if blocking.isAuthorized { openPicker() }
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }

                    if earned.isEnabled {
                        spendCard
                    }

                    distractingCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How you earn")
                            .font(.title3.weight(.semibold))
                        Picker("Mode", selection: Binding(get: { earned.pendingMode?.mode ?? earned.mode }, set: chooseMode)) {
                            ForEach(EarnMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if let pending = earned.pendingMode {
                            PendingNote(
                                text: "\(pending.mode.title) starts at \(pending.at.formatted(date: .omitted, time: .shortened)). Until then \(earned.mode.title) rules apply.",
                                cancel: earned.cancelPendingMode
                            )
                        } else {
                            Text("Easier modes start \(Int(EarnedTimeManager.loosenDelay / 60)) minutes after you pick them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                    ExchangeCard(mode: earned.mode)
                    DeepFocusCard(mode: earned.mode)
                    PriceCard(unlockedToday: earned.unlockedToday)
                    PassesCard(passesLeft: earned.passesLeft)
                }
                .padding()
                .animation(.spring(duration: 0.45), value: earned.mode)
            }
            .navigationTitle("Earned time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                confirmingMode.map { "Switch to \($0.title)?" } ?? "",
                isPresented: Binding(get: { confirmingMode != nil }, set: { if !$0 { confirmingMode = nil } }),
                presenting: confirmingMode
            ) { mode in
                Button("Switch in \(Int(EarnedTimeManager.loosenDelay / 60)) min") { earned.requestMode(mode) }
                Button("Keep \(earned.mode.title)", role: .cancel) {}
            } message: { mode in
                Text("\(mode.title) is easier, so it starts in \(Int(EarnedTimeManager.loosenDelay / 60)) minutes. That way it's a decision, not an impulse. Until then \(earned.mode.title) rules apply, and you can still cancel.")
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $draft)
            .onChange(of: showingPicker) { _, showing in
                // Cancelling the picker leaves the draft untouched; don't restart a pending cooldown then.
                if !showing && !Self.sameTokens(draft, draftStart) {
                    earned.requestDistracting(draft)
                }
            }
        }
    }

    /// Stricter modes apply right away; easier ones ask first, because they wait out the cooldown.
    private func chooseMode(_ mode: EarnMode) {
        if mode.isEasier(than: earned.mode) && earned.pendingMode?.mode != mode {
            confirmingMode = mode
        } else {
            earned.requestMode(mode)
        }
    }

    private func openPicker() {
        draft = earned.pendingDistracting?.selection ?? earned.distracting
        draftStart = draft
        showingPicker = true
    }

    private static func sameTokens(_ a: FamilyActivitySelection, _ b: FamilyActivitySelection) -> Bool {
        a.applicationTokens == b.applicationTokens
            && a.categoryTokens == b.categoryTokens
            && a.webDomainTokens == b.webDomainTokens
    }

    @ViewBuilder
    private var spendCard: some View {
        if let unlock = earned.activeUnlock, earned.isUnlocked {
            Card {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(max(0, unlock.endsAt.timeIntervalSince(context.date)).clockFormatted)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
                Text(unlock.cost > 0 ? "until apps lock again. Locking early gives back the unused time." : "left on your emergency pass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Lock now") { earned.lockNow() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Card {
                Text("Unlock distracting apps")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(EarnedTimeManager.unlockOptions, id: \.self) { minutes in
                        let affordable = earned.canAfford(minutes)
                        Button {
                            earned.unlock(minutes: minutes)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(Int(minutes)) min")
                                    .font(.headline)
                                Text("costs \((earned.cost(forMinutes: minutes) * 60).focusFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.15)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                        .opacity(affordable ? 1 : 0.35)
                    }
                }
                Button {
                    earned.useEmergencyPass()
                } label: {
                    Label("Use an emergency pass (5 min)", systemImage: "cross.case")
                        .font(.subheadline)
                }
                .disabled(earned.passesLeft == 0)

                if let error = earned.scheduleError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var distractingCard: some View {
        Card {
            Text("Distracting apps")
                .font(.subheadline.weight(.medium))
            Text("These stay blocked until you spend earned time on them. Removing one takes \(Int(EarnedTimeManager.loosenDelay / 60)) minutes to apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if earned.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(earned.distracting.categoryTokens), id: \.self) { Label($0) }
                    ForEach(Array(earned.distracting.applicationTokens), id: \.self) { Label($0) }
                    ForEach(Array(earned.distracting.webDomainTokens), id: \.self) { Label($0) }
                }
                .font(.subheadline)
            }
            if earned.distracting.applicationTokens.count > ScreenTime.maxTokens {
                Text("iOS can block at most \(ScreenTime.maxTokens) individual apps, so some of these stay open. Pick a whole category to block more.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let pending = earned.pendingDistracting {
                PendingNote(
                    text: "Unblocking \(earned.pendingRemovalCount) at \(pending.at.formatted(date: .omitted, time: .shortened)).",
                    cancel: earned.cancelPendingDistracting
                )
            }
            Button(earned.isEnabled ? "Change" : "Choose distracting apps") {
                openPicker()
            }
            .font(.subheadline.weight(.semibold))
            .disabled(!blocking.isAuthorized)
        }
    }
}

/// A rule change waiting out its cooldown, with a way to call it off.
private struct PendingNote: View {
    let text: String
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: cancel)
                .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }
}

/// Balance as a ring that fills toward the saving cap.
private struct BalanceRing: View {
    let balance: Double
    let cap: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(1, balance / cap))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text((balance * 60).focusFormatted)
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("earned")
                    .foregroundStyle(.secondary)
                Text("save up to \(Int(cap))m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 200, height: 200)
    }
}

private struct CardTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
    }
}

/// N faint blocks of focus turn into one solid block of scrolling.
private struct ExchangeCard: View {
    let mode: EarnMode

    var body: some View {
        let focusBlocks = Int(mode.focusPerMinute)
        let perHour = 60 / mode.focusPerMinute

        Card {
            CardTitle(title: "The exchange rate", icon: "arrow.left.arrow.right")

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<focusBlocks, id: \.self) { _ in
                        block(filled: false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                block(filled: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            HStack {
                Text("\(focusBlocks) min of focus")
                Spacer()
                Text("1 min of scrolling")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("1 hour of focus")
                Spacer()
                Text("\(Int(perHour))m of scrolling")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fontWeight(.medium)
            }
            .font(.subheadline)
        }
    }

    private func block(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(filled ? Color.primary : Color.primary.opacity(0.15))
            .frame(width: 34, height: 34)
    }
}

/// A one-hour timeline where the bonus kicks in at 45 minutes.
private struct DeepFocusCard: View {
    let mode: EarnMode

    var body: some View {
        let split = EarnedTimeManager.deepFocusThreshold / 3600
        let normalHour = 60 / mode.focusPerMinute
        let bonusHour = normalHour * EarnedTimeManager.deepFocusBonus

        Card {
            CardTitle(title: "Deep focus bonus", icon: "flame")

            GeometryReader { geometry in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: (geometry.size.width - 3) * split)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary)
                }
            }
            .frame(height: 14)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Text("0")
                    Text("45 min")
                        .fixedSize()
                        .offset(x: geometry.size.width * split - 20)
                    Text("1 h")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 14)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Focus for **45 minutes or more** in one go, and that whole session earns **50% more** scrolling time.")
                .font(.subheadline)

            Divider()

            HStack {
                Text("A 1 hour session earns")
                Spacer()
                Text("\(Int(normalHour))m")
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text("\(Int(bonusHour))m")
                    .fontWeight(.medium)
                    .contentTransition(.numericText())
            }
            .font(.subheadline)
            .monospacedDigit()
        }
    }
}

/// Step bars for the daily price tiers, with today's tier highlighted.
private struct PriceCard: View {
    let unlockedToday: Double

    private let labels = ["First 30 min", "Next 30 min", "After 1 h"]

    var body: some View {
        let tiers = EarnedTimeManager.priceTiers
        let current = tiers.firstIndex { unlockedToday < $0.upTo } ?? tiers.count - 1

        Card {
            CardTitle(title: "Scrolling costs more the more you scroll", icon: "chart.bar.fill")

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(tiers.indices, id: \.self) { index in
                    let isCurrent = index == current
                    VStack(spacing: 6) {
                        Text("\(tiers[index].rate.formatted())×")
                            .font(.system(.headline, design: .rounded))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCurrent ? Color.primary : Color.primary.opacity(0.15))
                            .frame(height: 30 * tiers[index].rate)
                        Text(labels[index])
                            .font(.caption)
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                        Text(isCurrent ? "now" : " ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)

            Text("Each minute of scrolling you unlock is paid with earned time. Your first 30 minutes of the day cost 1 minute each, the next 30 cost 1.5, and after an hour every minute costs 2. So 15 minutes costs 15m at first, but 30m late in the day. It resets at midnight.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PassesCard: View {
    let passesLeft: Int

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    CardTitle(title: "Emergency passes", icon: "cross.case")
                    Text("5 min each, free. \(passesLeft) left today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<EarnedTimeManager.passesPerDay, id: \.self) { index in
                        Circle()
                            .fill(index < passesLeft ? Color.primary : Color.primary.opacity(0.12))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }
}

/// Small pill on the home screen: earned balance, or time left while unlocked.
struct EarnedBadge: View {
    @Environment(EarnedTimeManager.self) private var earned

    var body: some View {
        Group {
            if let unlock = earned.activeUnlock, earned.isUnlocked {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label("\(max(0, unlock.endsAt.timeIntervalSince(context.date)).clockFormatted) unlocked", systemImage: "lock.open")
                }
            } else {
                Label("\((earned.balance * 60).focusFormatted) earned", systemImage: "lock")
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}
