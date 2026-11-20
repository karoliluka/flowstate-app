import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

/// The signed-in account (optional: everything except study groups works without one).
@MainActor
@Observable
final class AccountManager {
    private(set) var user: User?
    private(set) var profile: MemberProfile?

    var isSignedIn: Bool { user != nil }
    var email: String? { user?.email }

    /// Raw nonce for the Sign in with Apple request in progress; Apple gets its hash.
    private var appleNonce: String?

    init() {
        Task { await listen() }
    }

    private func listen() async {
        for await (_, session) in Backend.client.auth.authStateChanges {
            // An expired stored session is refreshed in the background; until then treat it as signed in.
            user = session?.user
            if user != nil {
                await loadProfile()
            } else {
                profile = nil
            }
        }
    }

    func loadProfile() async {
        guard let id = user?.id else { return }
        profile = try? await Backend.client.from("profiles").select().eq("id", value: id).single().execute().value
    }

    // MARK: Email

    /// Returns true when Supabase wants the email confirmed before the first sign-in.
    func signUp(email: String, password: String, firstName: String, lastName: String) async throws -> Bool {
        let response = try await Backend.client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            data: ["first_name": .string(firstName), "last_name": .string(lastName)],
            redirectTo: Backend.authRedirect
        )
        return response.session == nil
    }

    func signIn(email: String, password: String) async throws {
        try await Backend.client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
    }

    // MARK: Apple

    /// Fills in the Sign in with Apple request: name and email, plus a nonce that ties Apple's
    /// answer to this request so it can't be replayed.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization = try result.get()
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8),
            let nonce = appleNonce
        else { throw AccountError.appleSignInFailed }

        try await Backend.client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
        // Apple shares the name only the very first time someone signs in to the app.
        if let name = credential.fullName, name.givenName != nil || name.familyName != nil {
            try? await updateName(first: name.givenName ?? "", last: name.familyName ?? "")
        }
    }

    // MARK: Google

    /// Opens Google's sign-in page in a secure browser sheet and comes back to flowstate://auth-callback.
    func signInWithGoogle() async throws {
        try await Backend.client.auth.signInWithOAuth(provider: .google, redirectTo: Backend.authRedirect)
    }

    /// Finishes sign-ins that come back as a link (email confirmation).
    func handle(_ url: URL) {
        Backend.client.auth.handle(url)
    }

    // MARK: Account

    func updateName(first: String, last: String) async throws {
        guard let id = user?.id else { return }
        struct Name: Encodable {
            let first_name: String
            let last_name: String
        }
        let name = Name(first_name: String(first.trimmingCharacters(in: .whitespaces).prefix(40)),
                        last_name: String(last.trimmingCharacters(in: .whitespaces).prefix(40)))
        try await Backend.client.from("profiles").update(name).eq("id", value: id).execute()
        await loadProfile()
    }

    func signOut() async {
        try? await Backend.client.auth.signOut()
        user = nil
        profile = nil
    }

    /// Deletes the account on the server (profile, group memberships, login) and signs out.
    /// Sessions on the phone aren't touched; they never left it.
    func deleteAccount() async throws {
        try await Backend.client.rpc("delete_my_account").execute()
        try? await Backend.client.auth.signOut(scope: .local)
        user = nil
        profile = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }
}

enum AccountError: LocalizedError {
    case appleSignInFailed

    var errorDescription: String? {
        switch self {
        case .appleSignInFailed: "Sign in with Apple didn't finish. Try again."
        }
    }
}
