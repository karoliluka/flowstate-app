import Foundation
import Supabase

/// The Supabase project behind accounts and study groups (database setup: supabase/schema.sql).
enum Backend {
    static let url = URL(string: "https://dppftyrxttmbmsvemdmg.supabase.co")!
    /// The publishable key is meant to ship inside the app; row level security in the database
    /// decides what each signed-in person may read or change.
    static let publishableKey = "sb_publishable_mVw8jm_BpLYid0RAgdhqrA_RQneXaKX"
    /// Where sign-in links and Google sign-in come back to (also listed in Supabase → Auth → URL Configuration).
    static let authRedirect = URL(string: "flowstate://auth-callback")!

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            auth: .init(redirectToURL: authRedirect, emitLocalSessionAsInitialSession: true)
        )
    )

    /// Sign in with Apple needs a paid developer team, which the free-account Preview build doesn't have.
    #if PREVIEW && !TESTFLIGHT
    static let appleSignInAvailable = false
    #else
    static let appleSignInAvailable = true
    #endif
}

/// A person as their group mates see them.
struct MemberProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var totalSeconds: Int64
    /// "yyyy-MM-dd", the Monday that `weekSeconds` belongs to.
    var weekStart: String?
    var weekSeconds: Int64
    var activeSince: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case totalSeconds = "total_seconds"
        case weekStart = "week_start"
        case weekSeconds = "week_seconds"
        case activeSince = "active_since"
    }

    var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Someone" : name
    }

    /// This week's focus, or zero if their last report was from an earlier week.
    func secondsThisWeek(now: Date = .now) -> TimeInterval {
        weekStart == GroupStats.weekStartString(for: now) ? TimeInterval(weekSeconds) : 0
    }

    /// Focusing right now. Sessions left running for over 12 hours (app deleted, phone off) don't count.
    func isActive(now: Date = .now) -> Bool {
        guard let activeSince else { return false }
        return now.timeIntervalSince(activeSince) < 12 * 3600
    }
}

struct StudyGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var ownerID: UUID?
    var inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case inviteCode = "invite_code"
    }
}

/// What an invite shows before joining.
struct GroupPreview: Decodable, Hashable {
    let groupName: String
    let ownerFirstName: String
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
        case ownerFirstName = "owner_first_name"
        case memberCount = "member_count"
    }
}
