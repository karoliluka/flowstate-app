import SwiftUI
import SwiftData

struct FocusView: View {
    @Environment(SessionManager.self) private var session
    @Environment(BlockingManager.self) private var blocking

    @Query(sort: \Subject.createdAt) private var subjects: [Subject]
    @Query private var todaySessions: [FocusSession]

    @AppStorage(StorageKeys.selectedSubjectID) private var selectedSubjectID = ""
    @AppStorage(StorageKeys.username) private var username = ""
    @State private var showingAllowedApps = false
    @State private var showingProfile = false
    @State private var showingNewSubject = false
    @State private var showingEarned = false


    /// `today` comes from RootView and changes at midnight, which rebuilds the query.
    init(today: Date) {
        _todaySessions = Query(filter: #Predicate<FocusSession> { $0.startedAt >= today })
    }

    /// The chosen subject, falling back to the first one so a subject is always selected once any exist.
    private var selectedSubject: Subject? {
        subjects.first { $0.uuid.uuidString == selectedSubjectID } ?? subjects.first
    }

    private var focusedToday: TimeInterval {
        todaySessions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 6) {
                    Text(focusedToday.focusFormatted)
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("focused today")
                        .foregroundStyle(.secondary)

                    Button { showingEarned = true } label: { EarnedBadge() }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                }

                Spacer()

                if ScreenTime.isAvailable && !blocking.isAuthorized {
                    AuthorizationCard(onAuthorized: { showingAllowedApps = true })
                        .padding(.horizontal)
                }

                SubjectChips(
                    subjects: subjects,
                    selected: selectedSubject,
                    onSelect: { selectedSubjectID = $0.uuid.uuidString },
                    onAdd: { showingNewSubject = true }
                )

                Button {
                    session.start(subject: selectedSubject)
                } label: {
                    Text("Start focus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAllowedApps = true
                    } label: {
                        Image(systemName: "app.badge.checkmark")
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .onAppear {
                // Launch with `-debugSheet earned|profile|allowed` to open a sheet directly.
                switch UserDefaults.standard.string(forKey: "debugSheet") {
                case "allowed": showingAllowedApps = true
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
        }
    }
}

private struct SubjectChips: View {
    let subjects: [Subject]
    let selected: Subject?
    let onSelect: (Subject) -> Void
    let onAdd: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(subjects) { subject in
                    chip(subject: subject, isSelected: subject.uuid == selected?.uuid)
                }
                addButton
            }
            .padding(.horizontal)
        }
    }

    /// Spelled out until the first subject exists, then just a "+".
    @ViewBuilder
    private var addButton: some View {
        Button(action: onAdd) {
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
        .buttonStyle(.plain)
        .accessibilityLabel("Add subject")
    }

    private func chip(subject: Subject, isSelected: Bool) -> some View {
        Button { onSelect(subject) } label: {
            HStack(spacing: 6) {
                Circle().fill(subject.color).frame(width: 8, height: 8)
                Text(subject.name).font(.subheadline)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(isSelected ? Color.primary.opacity(0.1) : .clear))
            .overlay(Capsule().strokeBorder(isSelected ? Color.primary.opacity(0.4) : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
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

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(Color(.systemBackground))
            .background(Capsule().fill(Color.primary))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
