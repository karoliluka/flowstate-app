import Foundation
import Supabase
import SwiftData

/// Talks to the study-group tables. Every call runs as the signed-in person, and the database's
/// row level security only lets them see groups they're in and the people in those groups.
enum GroupService {
    private static var client: SupabaseClient { Backend.client }

    static var isSignedIn: Bool { client.auth.currentUser != nil }

    static func myGroups() async throws -> [StudyGroup] {
        try await client.from("groups").select("id, name, owner_id, invite_code").order("created_at").execute().value
    }

    /// Everyone in the group with their shared numbers.
    static func members(of group: StudyGroup) async throws -> [MemberProfile] {
        struct Membership: Decodable { let user_id: UUID }
        let memberships: [Membership] = try await client.from("group_members")
            .select("user_id").eq("group_id", value: group.id).execute().value
        guard !memberships.isEmpty else { return [] }
        return try await client.from("profiles")
            .select().in("id", values: memberships.map(\.user_id)).execute().value
    }

    static func create(named name: String) async throws -> StudyGroup {
        try await client.rpc("create_group", params: ["group_name": name]).execute().value
    }

    static func join(code: String) async throws -> StudyGroup {
        try await client.rpc("join_group", params: ["code": code]).execute().value
    }

    /// The group behind an invite code, or nil if there's none.
    static func preview(code: String) async throws -> GroupPreview? {
        let rows: [GroupPreview] = try await client.rpc("group_preview", params: ["code": code]).execute().value
        return rows.first
    }

    static func leave(_ group: StudyGroup) async throws {
        guard let me = client.auth.currentUser?.id else { return }
        try await client.from("group_members").delete().eq("group_id", value: group.id).eq("user_id", value: me).execute()
    }

    // MARK: Sharing my numbers

    /// Sends this phone's totals (and whether a session is running) to the profile group mates see.
    /// Does nothing when signed out; failures are ignored and retried at the next chance.
    @MainActor
    static func sync(context: ModelContext, activeSince: Date?) {
        guard let me = client.auth.currentUser?.id else { return }
        let totals = GroupStats.totals(in: context)
        let update = StatsUpdate(
            totalSeconds: Int64(totals.total),
            weekStart: totals.weekStart,
            weekSeconds: Int64(totals.thisWeek),
            activeSince: activeSince
        )
        Task {
            try? await client.from("profiles").update(update).eq("id", value: me).execute()
        }
    }

    private struct StatsUpdate: Encodable {
        let totalSeconds: Int64
        let weekStart: String
        let weekSeconds: Int64
        let activeSince: Date?

        enum CodingKeys: String, CodingKey {
            case totalSeconds = "total_seconds"
            case weekStart = "week_start"
            case weekSeconds = "week_seconds"
            case activeSince = "active_since"
            case updatedAt = "updated_at"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(totalSeconds, forKey: .totalSeconds)
            try container.encode(weekStart, forKey: .weekStart)
            try container.encode(weekSeconds, forKey: .weekSeconds)
            // Written out as null when the session ends, so "focusing now" switches off.
            if let activeSince {
                try container.encode(activeSince, forKey: .activeSince)
            } else {
                try container.encodeNil(forKey: .activeSince)
            }
            try container.encode(Date.now, forKey: .updatedAt)
        }
    }
}
