import SwiftUI

/// Opens the Groups sheet and carries invite codes from links or the clipboard to it.
@MainActor
@Observable
final class GroupsRouter {
    static let shared = GroupsRouter()

    var showingGroups = false
    /// An invite waiting to be answered. Kept across launches, so signing up in between doesn't lose it.
    var pendingInvite: String? {
        didSet { UserDefaults.standard.set(pendingInvite, forKey: Self.pendingKey) }
    }

    private static let pendingKey = "groups.pendingInvite"

    private init() {
        pendingInvite = UserDefaults.standard.string(forKey: Self.pendingKey)
    }

    func open(invite code: String) {
        pendingInvite = code
        showingGroups = true
    }
}

/// Study groups: a list of yours, plus creating and joining. Asks you to sign in first.
struct GroupsView: View {
    @Environment(AccountManager.self) private var account
    @Environment(GroupsRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [StudyGroup] = []
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false
    @State private var newGroupName = ""
    @State private var joinText = ""

    var body: some View {
        NavigationStack {
            Group {
                if !account.isSignedIn {
                    ScrollView {
                        SignInView(reason: router.pendingInvite == nil
                                   ? "Study groups need an account, so your group mates can see you."
                                   : "Sign in to join the group you were invited to.")
                            .padding()
                    }
                } else if let code = router.pendingInvite {
                    JoinInviteView(code: code) { joined in
                        router.pendingInvite = nil
                        if let joined { groups.append(joined) }
                        Task { await load() }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: StudyGroup.self) { group in
                GroupDetailView(group: group) {
                    groups.removeAll { $0.id == group.id }
                }
            }
            .task(id: account.isSignedIn) { await load() }
            .alert("New group", isPresented: $creating) {
                TextField("Name, e.g. Physics crew", text: $newGroupName)
                Button("Create") { Task { await create() } }
                Button("Cancel", role: .cancel) { newGroupName = "" }
            } message: {
                Text("You can invite people right after.")
            }
        }
    }

    private var list: some View {
        List {
            if !groups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        NavigationLink(value: group) {
                            Label(group.name, systemImage: "person.2.fill")
                                .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section {
                Button {
                    newGroupName = ""
                    creating = true
                } label: {
                    Label("Create a group", systemImage: "plus")
                }
            } footer: {
                if groups.isEmpty && !loading {
                    Text("Focus together: see who's focusing right now and who leads this week.")
                }
            }

            Section {
                HStack {
                    TextField("Invite link or code", text: $joinText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit(joinFromText)
                    // One tap, and no "allow paste?" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first {
                            joinText = text
                            joinFromText()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            } header: {
                Text("Join a group")
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if loading && groups.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
    }

    private func joinFromText() {
        guard let code = InviteLink.code(fromText: joinText) else {
            error = "That doesn't look like an invite link or code."
            return
        }
        error = nil
        joinText = ""
        router.pendingInvite = code
    }

    private func load() async {
        guard account.isSignedIn else { return }
        loading = true
        defer { loading = false }
        do {
            groups = try await GroupService.myGroups()
            error = nil
        } catch {
            self.error = "Couldn't load your groups. Pull down to try again."
        }
    }

    private func create() async {
        let name = SubjectEditor.normalizedName(newGroupName)
        guard !name.isEmpty else { return }
        do {
            groups.append(try await GroupService.create(named: String(name.prefix(40))))
        } catch {
            self.error = "Couldn't create the group. Check your connection and try again."
        }
    }
}

/// "Join Physics crew?" for an invite, after signing in.
struct JoinInviteView: View {
    let code: String
    /// The joined group, or nil when declined.
    let onFinish: (StudyGroup?) -> Void

    @State private var preview: GroupPreview?
    @State private var state: LoadState = .loading
    @State private var joining = false

    private enum LoadState { case loading, found, notFound, failed }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: state == .found)

            switch state {
            case .loading:
                ProgressView()
            case .found:
                if let preview {
                    VStack(spacing: 6) {
                        Text("Join \(preview.groupName)?")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(detail(preview))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            case .notFound:
                Text("This invite doesn't work anymore. Ask for a new link.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed:
                Text("Couldn't check the invite. Check your connection.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if state == .found {
                Button {
                    Task { await join() }
                } label: {
                    if joining { ProgressView().tint(Color(.systemBackground)) } else { Text("Join group") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(joining)
            }
            Button(state == .found ? "Not now" : "Close") { onFinish(nil) }
                .hitTarget()
        }
        .padding()
        .task { await load() }
    }

    private func detail(_ preview: GroupPreview) -> String {
        let people = preview.memberCount == 1 ? "1 member" : "\(preview.memberCount) members"
        return preview.ownerFirstName.isEmpty ? people : "\(preview.ownerFirstName)'s group · \(people)"
    }

    private func load() async {
        do {
            preview = try await GroupService.preview(code: code)
            state = preview == nil ? .notFound : .found
        } catch {
            state = .failed
        }
    }

    private func join() async {
        joining = true
        defer { joining = false }
        if let group = try? await GroupService.join(code: code) {
            onFinish(group)
        } else {
            state = .failed
        }
    }
}
