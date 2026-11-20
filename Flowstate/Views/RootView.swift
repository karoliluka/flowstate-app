import SwiftUI
import SwiftData
import Combine

struct RootView: View {
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(NotificationRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StorageKeys.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(StorageKeys.selectedTab) private var selectedTab = 0
    /// Moves on at midnight, so "today" totals and stats ranges don't go stale while the app stays open.
    @State private var today = Calendar.current.startOfDay(for: .now)
    /// New every time the app opens, so the "That's like" comparisons change.
    @State private var comparisonSeed = UInt64.random(in: .min ... .max)

    var body: some View {
        @Bindable var router = router

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
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Coming back or leaving: give the Live Activity fresh goals for the time already focused.
            if phase != .inactive { session.syncLiveActivity(in: context) }
        }
        .sheet(item: $router.recap) { week in
            WeeklyRecapView(weekStart: week.start)
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
