import SwiftUI
import UIKit
import SwiftData
import Combine

struct RootView: View {
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(NotificationRouter.self) private var router
    @Environment(GroupsRouter.self) private var groups
    @Environment(AccountManager.self) private var account
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StorageKeys.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(StorageKeys.selectedTab) private var selectedTab = 0
    /// Moves on at midnight, so "today" totals and stats ranges don't go stale while the app stays open.
    @State private var today = Calendar.current.startOfDay(for: .now)
    /// New every time the app opens, so the "That's like" comparisons change.
    @State private var comparisonSeed = UInt64.random(in: .min ... .max)
    @State private var showingInvitePrompt = false
    @AppStorage("groups.checkedClipboardOnFirstLaunch") private var checkedClipboard = false

    var body: some View {
        @Bindable var router = router
        @Bindable var groups = groups

        TabView(selection: $selectedTab) {
            FocusView(today: today)
                .tabItem { Label("Focus", systemImage: "stopwatch") }
                .tag(0)
            SubjectsView()
                .tabItem { Label("Subjects", systemImage: "square.stack") }
                .tag(1)
            StatsView(today: today)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(2)
        }
        // The session screen can only be left by ending the session, then closing its summary.
        .fullScreenCover(isPresented: Binding(get: { session.isActive || session.summary != nil }, set: { _ in })) {
            ActiveSessionView()
        }
        .onChange(of: appearance, initial: true) { _, mode in
            mode.apply()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Screen Time access may have been turned off in Settings meanwhile.
                blocking.refreshAuthorization()
                today = Calendar.current.startOfDay(for: .now)
                comparisonSeed = UInt64.random(in: .min ... .max)
                Task { await FocusNotifications.reschedule(context: context) }
                GroupService.sync(context: context, activeSince: session.startedAt)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Coming back or leaving: give the Live Activity fresh goals for the time already focused.
            if phase != .inactive { session.syncLiveActivity(in: context) }
        }
        .sheet(item: $router.recap) { week in
            WeeklyRecapView(weekStart: week.start)
        }
        .sheet(isPresented: $groups.showingGroups) {
            GroupsView()
        }
        .sheet(isPresented: $showingInvitePrompt) {
            InvitePromptView()
        }
        // Group mates see "focusing now" from the moment a session starts until it ends.
        .onChange(of: session.startedAt) { _, startedAt in
            GroupService.sync(context: context, activeSince: startedAt)
        }
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn { GroupService.sync(context: context, activeSince: session.startedAt) }
        }
        .onOpenURL { url in
            if let code = InviteLink.code(from: url) {
                groups.open(invite: code)
            } else {
                account.handle(url)
            }
        }
        .task {
            // Installed from an invite page? The page copied the link, so offer to paste it once.
            guard !checkedClipboard else { return }
            checkedClipboard = true
            try? await Task.sleep(for: .seconds(3.2)) // after the intro
            guard groups.pendingInvite == nil, await Self.clipboardHasLink() else { return }
            showingInvitePrompt = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            today = Calendar.current.startOfDay(for: .now)
        }
        .environment(\.comparisonSeed, comparisonSeed)
        #if DEBUG
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-loadSampleData") {
                SampleData.replaceAll(in: context)
            }
            // `-startSession` begins a session right away, e.g. to check the Live Activity.
            if arguments.contains("-startSession") && !session.isActive {
                session.start(subject: try? context.fetch(FetchDescriptor<Subject>()).first)
            }
        }
        #endif
    }
}

extension RootView {
    /// Whether the clipboard probably holds a link, checked without reading it (so no paste prompt).
    static func clipboardHasLink() async -> Bool {
        guard UIPasteboard.general.hasStrings else { return false }
        return await withCheckedContinuation { continuation in
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                continuation.resume(returning: (try? result.get())?.contains(.probableWebURL) ?? false)
            }
        }
    }
}

/// Shown once on first launch when the clipboard holds a link: someone may have tapped
/// "Get flowstate" on an invite page, which copied their invite.
private struct InvitePromptView: View {
    @Environment(GroupsRouter.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var notAnInvite = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .padding(.top, 28)
            Text("Got a study group invite?")
                .font(.title3.weight(.semibold))
            Text("If someone sent you an invite link, paste it to join their group.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if notAnInvite {
                Text("That's not an invite link. You can also join later from Groups.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in
                    if let code = strings.first.flatMap(InviteLink.code(fromText:)) {
                        dismiss()
                        groups.open(invite: code)
                    } else {
                        notAnInvite = true
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            Button("Not now") { dismiss() }
                .hitTarget()
        }
        .padding()
        .presentationDetents([.medium])
    }
}
