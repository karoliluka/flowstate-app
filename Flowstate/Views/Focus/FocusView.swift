import SwiftUI
import SwiftData

struct FocusView: View {
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking
    @Environment(NotificationRouter.self) private var router

    @Query(sort: \Subject.createdAt) private var subjects: [Subject]
    @Query private var todaySessions: [FocusSession]

    @AppStorage(StorageKeys.selectedSubjectID) private var selectedSubjectID = ""
    @AppStorage(StorageKeys.username) private var username = ""
    @State private var showingAllowedApps = false
    @State private var showingProfile = false
    @State private var showingNewSubject = false
    @State private var showingEarned = false
    @State private var editingSubject: Subject?
    /// What "focused today" shows. Held back while the session screen covers it, so the new
    /// total rolls up where you can see it once you're back.
    @State private var displayedToday: TimeInterval?

    /// `today` comes from RootView and changes at midnight, which rebuilds the query.
    init(today: Date) {
        _todaySessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= today })
    }

    /// The chosen subject, falling back to the first one so a subject is always selected once any exist.
    private var selectedSubject: Subject? {
        subjects.first { $0.uuid.uuidString == selectedSubjectID } ?? subjects.first
    }

    /// Most-used subjects first (frequency of use), newest last among equals.
    private var subjectsByUse: [Subject] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let uses = Dictionary(uniqueKeysWithValues: subjects.map { subject in
            (subject.uuid, subject.sessions.lazy.filter { $0.startedAt >= cutoff }.count)
        })
        return subjects.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (uses[lhs.element.uuid] ?? 0, uses[rhs.element.uuid] ?? 0)
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var sessionScreenShowing: Bool {
        session.isActive || session.summary != nil
    }

    private var focusedToday: TimeInterval {
        todaySessions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 6) {
                    let shown = displayedToday ?? focusedToday
                    Text(shown.focusFormatted)
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: shown))
                        // A little bump when the total grows: the payoff for the session you just did.
                        .keyframeAnimator(initialValue: 1.0, trigger: shown) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.1, duration: 0.18, spring: .snappy)
                            SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                        }
                    Text("focused today")
                        .foregroundStyle(.secondary)

                    Button { showingEarned = true } label: { EarnedBadge().hitTarget() }
                        .buttonStyle(SquishButtonStyle(squash: CGSize(width: 0.94, height: 0.94)))
                        .padding(.top, 20)
                }
                .onChange(of: focusedToday) { _, _ in
                    if !sessionScreenShowing { displayedToday = nil }
                }
                .onChange(of: sessionScreenShowing) { _, showing in
                    if showing {
                        displayedToday = focusedToday
                    } else {
                        // Wait for the session screen to close, then roll up to the new total.
                        withAnimation(Motion.bouncy.delay(0.45)) { displayedToday = nil }
                    }
                }

                Spacer()

                if ScreenTime.isAvailable && !blocking.isAuthorized {
                    AuthorizationCard(onAuthorized: { showingAllowedApps = true })
                        .padding(.horizontal)
                }

                SubjectChips(
                    subjects: subjectsByUse,
                    selected: selectedSubject,
                    onSelect: { selectedSubjectID = $0.uuid.uuidString },
                    onAdd: { showingNewSubject = true },
                    onEdit: { editingSubject = $0 }
                )

                Button {
                    // The session screen grows out of this button itself (see ActiveSessionView),
                    // instead of the standard full-screen slide.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        session.start(subject: selectedSubject)
                    }
                } label: {
                    Text("Start focus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .sensoryFeedback(.impact(weight: .medium), trigger: session.isActive) { _, active in active }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAllowedApps = true
                    } label: {
                        Image(systemName: "app.badge.checkmark")
                            .hitTarget()
                    }
                    .accessibilityLabel("Allowed apps")
                }
                ToolbarItem(placement: .principal) {
                    Text("flowstate")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Avatar(username: username, size: 30)
                            .hitTarget()
                    }
                    .buttonStyle(SquishButtonStyle(squash: CGSize(width: 0.9, height: 0.9), haptic: false))
                    .accessibilityLabel("Profile")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .onAppear {
                // Launch with `-debugSheet earned|profile|allowed|recap` to open a sheet directly.
                switch UserDefaults.standard.string(forKey: "debugSheet") {
                case "allowed": showingAllowedApps = true
                case "recap": router.showRecap(for: .now)
                case "earned": showingEarned = true
                case "profile": showingProfile = true
                default: break
                }
            }
            #endif
            .sheet(isPresented: $showingAllowedApps) {
                AllowedAppsView()
            }
            .sheet(isPresented: $showingEarned) {
                EarnedTimeView()
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewSubject) {
                SubjectEditor(subject: nil) { newSubject in
                    selectedSubjectID = newSubject.uuid.uuidString
                }
            }
            .sheet(item: $editingSubject) { subject in
                SubjectEditor(subject: subject)
            }
        }
    }
}

private struct SubjectChips: View {
    let subjects: [Subject]
    let selected: Subject?
    let onSelect: (Subject) -> Void
    let onAdd: () -> Void
    let onEdit: (Subject) -> Void

    @Namespace private var selection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjects) { subject in
                        chip(subject: subject, isSelected: subject.uuid == selected?.uuid)
                            .id(subject.uuid)
                    }
                    addButton
                }
                .padding(.horizontal)
            }
            .onAppear {
                if let id = selected?.uuid { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selected?.uuid) { _, id in
                if let id { withAnimation(Motion.snappy) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.uuid)
    }

    /// Spelled out until the first subject exists, then just a "+".
    @ViewBuilder
    private var addButton: some View {
        Button(action: onAdd) {
            Group {
                if subjects.isEmpty {
                    Label("Add subject", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                } else {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            .hitTarget()
        }
        .buttonStyle(SquishButtonStyle(squash: CGSize(width: 0.9, height: 0.9)))
        .accessibilityLabel("Add subject")
    }

    private func chip(subject: Subject, isSelected: Bool) -> some View {
        Button {
            withAnimation(Motion.snappy) { onSelect(subject) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(subject.color).frame(width: 8, height: 8)
                    .scaleEffect(isSelected ? 1.25 : 1)
                Text(subject.name).font(.subheadline)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                // One highlight that slides from chip to chip.
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.4)))
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.12)))
            .hitTarget()
        }
        .buttonStyle(SquishButtonStyle(squash: CGSize(width: 0.94, height: 0.94), haptic: false))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { onEdit(subject) }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AuthorizationCard: View {
    @Environment(BlockingManager.self) private var blocking
    let onAuthorized: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow Screen Time access")
                .font(.headline)
            Text("flowstate needs Screen Time permission to block distracting apps while you focus. Everything stays on your phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = blocking.authorizationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("Allow") {
                Task {
                    await blocking.requestAuthorization()
                    // Go straight to choosing allowed apps.
                    if blocking.isAuthorized { onAuthorized() }
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
    }
}

/// The big pill button at the bottom of the screen, in the thumb's reach.
/// Squashes on press and springs back with a little stretch.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(Color(.systemBackground))
            .background(Capsule().fill(Color.primary))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .modifier(SquishEffect(isPressed: configuration.isPressed, squash: CGSize(width: 1.03, height: 0.9)))
    }
}
