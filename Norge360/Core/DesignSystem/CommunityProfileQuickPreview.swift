import SwiftUI

/// Compact profile summary used by long-press and contextual community UI.
struct CommunityProfileQuickPreview: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var followStore: CommunityFollowStore
    let profile: CommunityProfile?
    @State private var stats: CommunityMemberProfileStats?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                CommunityAvatarView(url: profile?.avatarURL, size: 60)
                Text(profile?.displayName ?? AppStrings.localized("feed.member"))
                    .font(.headline)
                if let username = profile?.username {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                previewStat(followStore.states[profile?.userID ?? UUID()]?.followersCount ?? 0, "Followers")
                previewStat(followStore.states[profile?.userID ?? UUID()]?.followingCount ?? 0, "Following")
                previewStat(stats?.postsCount ?? 0, "Posts")
            }
        }
        .frame(width: 200, alignment: .leading)
        .padding(NorgeSpacing.medium)
        .task(id: profile?.userID) {
            guard let userID = profile?.userID else { return }
            stats = try? await feedStore.memberStats(for: userID)
            try? await followStore.loadState(for: userID)
        }
    }

    private func previewStat(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value, format: .number).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
