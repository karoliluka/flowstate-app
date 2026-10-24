import SwiftUI
import SwiftData
import UserNotifications

@main
struct FlowstateApp: App {
    @State private var blocking: BlockingManager
    @State private var session: SessionManager
    @State private var earned: EarnedTimeManager
    @State private var showingIntro = true
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        let blocking = BlockingManager()
        let earned = EarnedTimeManager()
        _blocking = State(initialValue: blocking)
        _earned = State(initialValue: earned)
        _session = State(initialValue: SessionManager(blocking: blocking, earned: earned))
        // Set before launch finishes, so tapping a notification that opened the app is handled.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared

        // Keep the store in the app's own container. By default SwiftData moves it into the
        // App Group when the build has one, so the Preview build (which doesn't) would see
        // different data than the full build.
        do {
            modelContainer = try ModelContainer(
                for: Subject.self, FocusSession.self,
                configurations: ModelConfiguration(groupContainer: .none)
            )
        } catch {
            fatalError("Couldn't open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(blocking)
                    .environment(session)
                    .environment(earned)
                    .environment(NotificationRouter.shared)
                // The app switcher shows a snapshot taken as the app leaves: make it the logo.
                if scenePhase != .active && !showingIntro {
                    LogoScreen()
                        .zIndex(1)
                }
                if showingIntro {
                    IntroView {
                        withAnimation(.easeInOut(duration: 0.9)) { showingIntro = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
