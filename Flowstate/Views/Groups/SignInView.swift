import AuthenticationServices
import SwiftUI

/// Sign in or create an account: Apple, Google, or email and password.
struct SignInView: View {
    var reason: String = "Study groups need an account, so your group mates can see you."

    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    @State private var creatingAccount = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false
    @FocusState private var focused: Field?

    private enum Field { case first, last, email, password }

    var body: some View {
        VStack(spacing: 14) {
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            if Backend.appleSignInAvailable {
                SignInWithAppleButton(.continue) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    run { try await account.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(Capsule())
            }

            Button {
                run { try await account.signInWithGoogle() }
            } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25)))
                    .contentShape(Capsule())
            }
            .buttonStyle(SquishButtonStyle(squash: CGSize(width: 0.97, height: 0.94)))

            HStack {
                line
                Text("or").font(.footnote).foregroundStyle(.secondary)
                line
            }
            .padding(.vertical, 4)

            VStack(spacing: 10) {
                if creatingAccount {
                    HStack(spacing: 10) {
                        field("First name", text: $firstName, field: .first)
                            .textContentType(.givenName)
                        field("Last name", text: $lastName, field: .last)
                            .textContentType(.familyName)
                    }
                }
                field("Email", text: $email, field: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(creatingAccount ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submitEmail)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isError ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: submitEmail) {
                if busy {
                    ProgressView().tint(Color(.systemBackground))
                } else {
                    Text(creatingAccount ? "Create account" : "Sign in")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || !emailFormReady)
            .opacity(emailFormReady ? 1 : 0.4)

            Button(creatingAccount ? "Already have an account? Sign in" : "New here? Create an account") {
                withAnimation(Motion.snappy) {
                    creatingAccount.toggle()
                    message = nil
                }
            }
            .font(.subheadline)
            .hitTarget()
        }
        .animation(Motion.snappy, value: message)
    }

    private var line: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .focused($focused, equals: field)
            .submitLabel(.next)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var emailFormReady: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let hasName = !creatingAccount || !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        return trimmedEmail.contains("@") && password.count >= (creatingAccount ? 8 : 1) && hasName
    }

    private func submitEmail() {
        guard emailFormReady else {
            if creatingAccount && password.count < 8 { show("Use at least 8 characters for the password.", error: true) }
            return
        }
        if creatingAccount {
            run {
                let needsConfirmation = try await account.signUp(email: email, password: password,
                                                                 firstName: SubjectEditor.normalizedName(firstName),
                                                                 lastName: SubjectEditor.normalizedName(lastName))
                if needsConfirmation {
                    show("Almost there: open the link we emailed to \(email.trimmingCharacters(in: .whitespaces)), then sign in.", error: false)
                    creatingAccount = false
                }
            }
        } else {
            run { try await account.signIn(email: email, password: password) }
        }
    }

    /// Runs a sign-in step with a spinner, turning failures into a short message.
    private func run(_ step: @escaping () async throws -> Void) {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                try await step()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // Closed the Apple sheet: nothing to say.
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Closed the Google sheet.
            } catch {
                show(Self.describe(error), error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        isError = error
        message = text
    }

    private static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return "Wrong email or password." }
        if text.localizedCaseInsensitiveContains("not confirmed") { return "Confirm your email first: open the link we sent you." }
        if text.localizedCaseInsensitiveContains("already registered") { return "There's already an account with this email. Sign in instead." }
        if text.localizedCaseInsensitiveContains("provider is not enabled") { return "This sign-in option isn't switched on yet." }
        return text
    }
}
