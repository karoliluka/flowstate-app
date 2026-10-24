import SwiftUI
import Combine

struct RootView: View {
    @Environment(SessionManager.self) private var session
    @Environment(EarnedTimeManager.self) private var earned
    @Environment(BlockingManager.self) private var blocking
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StorageKeys.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(StorageKeys.selectedTab) private var selectedTab = 0
    /// Moves on at midnight, so "today" totals and stats ranges don't go stale while the app stays open.
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
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
                earned.refresh()
                today = Calendar.current.startOfDay(for: .now)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            today = Calendar.current.startOfDay(for: .now)
        }
        .task {
            // Re-block as soon as an unlock runs out while the app is open.
            while !Task.isCancelled {
                earned.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-loadSampleData") {
                SampleData.replaceAll(in: context)
                earned.debugAddBalance(34)
            }
        }
        #endif
    }
}
