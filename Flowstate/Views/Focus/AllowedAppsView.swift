import SwiftUI
import FamilyControls

struct AllowedAppsView: View {
    @Environment(BlockingManager.self) private var blocking
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    /// Apps worth allowing so nobody is cut off from help. Apple doesn't let apps
    /// preselect other apps, so these are suggestions the user picks themselves.
    private let suggestions: [(name: String, icon: String, reason: String)] = [
        ("Messages", "message.fill", "Stay reachable for family"),
        ("Maps", "map.fill", "Find your way"),
        ("Clock", "alarm.fill", "Alarms and timers"),
        ("Others", "ellipsis.circle.fill", "Anything you need for your work, like a calculator or dictionary"),
    ]

    var body: some View {
        @Bindable var blocking = blocking

        NavigationStack {
            List {
                Section {
                    Text("During a focus session every app is blocked except the ones you allow here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("Phone and emergency calls", systemImage: "phone.fill")
                } header: {
                    Text("Always available")
                } footer: {
                    Text("flowstate will never block incoming or emergency phone calls. Apps in Settings → Screen Time → Always Allowed stay open too.")
                }

                if blocking.isAuthorized {
                    let allowed = blocking.allowed
                    Section {
                        if allowed.applicationTokens.isEmpty && allowed.categoryTokens.isEmpty && allowed.webDomainTokens.isEmpty {
                            Text("None yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(allowed.categoryTokens), id: \.self) { Label($0) }
                            ForEach(Array(allowed.applicationTokens), id: \.self) { Label($0) }
                            ForEach(Array(allowed.webDomainTokens), id: \.self) { Label($0) }
                        }
                        Button("Choose apps") { showingPicker = true }
                    } header: {
                        Text("Your allowed apps")
                    } footer: {
                        if allowed.applicationTokens.count > ScreenTime.maxTokens {
                            Text("iOS lets flowstate keep at most \(ScreenTime.maxTokens) apps open, so only \(ScreenTime.maxTokens) of these \(allowed.applicationTokens.count) are allowed.")
                                .foregroundStyle(.orange)
                        }
                    }
                } else if !ScreenTime.isAvailable {
                    Section {
                        Text("App blocking is off in this preview build.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button("Allow Screen Time access") {
                            Task {
                                await blocking.requestAuthorization()
                                if blocking.isAuthorized { showingPicker = true }
                            }
                        }
                        if let error = blocking.authorizationError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    ForEach(suggestions, id: \.name) { suggestion in
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.icon)
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                Text(suggestion.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Suggested")
                } footer: {
                    Text("For privacy and other reasons, flowstate lets you choose apps yourself. Tap Choose apps and select the ones you want to keep.")
                }
            }
            .navigationTitle("Allowed apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $blocking.allowed)
        }
    }
}
