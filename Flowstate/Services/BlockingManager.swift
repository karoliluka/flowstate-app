import Foundation
import FamilyControls

/// Wraps Screen Time: authorization, the user's allowed apps, and turning the focus block on/off.
///
/// Blocking works as an allowlist: during a session every app is shielded
/// except the ones the user explicitly allowed.
@MainActor
@Observable
final class BlockingManager {
    /// Apps (and websites) that stay usable during a focus session. Stored in the
    /// App Group, next to the distracting apps the extension reads.
    var allowed: FamilyActivitySelection {
        didSet { SharedSettings.saveAllowed(allowed) }
    }

    private(set) var isAuthorized = false
    private(set) var authorizationError: String?

    init() {
        Self.migrateAllowedToAppGroup()
        allowed = SharedSettings.loadAllowed()
        refreshAuthorization()
    }

    func requestAuthorization() async {
        guard ScreenTime.isAvailable else {
            authorizationError = "App blocking is off in this preview build."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationError = nil
        } catch {
            authorizationError = error.localizedDescription
        }
        refreshAuthorization()
    }

    func refreshAuthorization() {
        isAuthorized = ScreenTime.isAvailable && AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func startBlocking() {
        guard isAuthorized else { return }
        FocusShield.apply()
    }

    func stopBlocking() {
        FocusShield.remove()
    }

    /// Allowed apps used to live in the app's own defaults; move them over once.
    private static func migrateAllowedToAppGroup() {
        let legacy = UserDefaults.standard
        guard
            SharedSettings.defaults.data(forKey: SharedSettings.allowedKey) == nil,
            let data = legacy.data(forKey: SharedSettings.allowedKey)
        else { return }
        SharedSettings.defaults.set(data, forKey: SharedSettings.allowedKey)
        legacy.removeObject(forKey: SharedSettings.allowedKey)
    }
}
