import SwiftUI
import SwiftData

@main
struct FlowstateApp: App {
    @State private var blocking: BlockingManager
    @State private var session: SessionManager
    @State private var earned: EarnedTimeManager
    private let modelContainer: ModelContainer

    init() {
        let blocking = BlockingManager()
        let earned = EarnedTimeManager()
        _blocking = State(initialValue: blocking)
        _earned = State(initialValue: earned)
        _session = State(initialValue: SessionManager(blocking: blocking, earned: earned))

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
            RootView()
                .environment(blocking)
                .environment(session)
                .environment(earned)
        }
        .modelContainer(modelContainer)
    }
}
