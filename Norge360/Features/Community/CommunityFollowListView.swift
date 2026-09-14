import SwiftUI

struct CommunityFollowListView: View {
    @EnvironmentObject private var followStore: CommunityFollowStore
    let userID: UUID
    let relationship: CommunityFollowListKind

    @State private var profiles: [CommunityProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState()
            } else if let errorMessage {
                VStack(spacing: 0) {
                    NorgeInlineFeedback(message: errorMessage)
                    NorgeUnavailableState(
                        AppStrings.localized("follow.unavailable"),
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                }
            } else if profiles.isEmpty {
                NorgeUnavailableState(
                    emptyTitle,
                    systemImage: "person.2",
                    description: emptyBody
                )
            } else {
                List(profiles) { profile in
                    NavigationLink {
                        CommunityMemberProfileView(userID: profile.userID)
                    } label: {
                        CommunityMemberIdentityView(
                            displayName: profile.displayName,
                            username: profile.username,
                            avatarURL: profile.avatarURL,
                            avatarSize: 46
                        )
                    }
                    .listRowBackground(Color.norgeAppBackground)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .norgeScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var title: String {
        AppStrings.localized("follow.\(relationship.rawValue)")
    }

    private var emptyTitle: String {
        AppStrings.localized("follow.empty_\(relationship.rawValue)_title")
    }

    private var emptyBody: String {
        AppStrings.localized("follow.empty_\(relationship.rawValue)_body")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await followStore.loadState(for: userID, forceRefresh: true)

            let state = followStore.states[userID]
            let relationshipCount: Int
            switch relationship {
            case .followers:
                relationshipCount = state?.followersCount ?? 0
            case .following:
                relationshipCount = state?.followingCount ?? 0
            }

            guard relationshipCount > 0 else {
                profiles = []
                return
            }

            profiles = try await followStore.profiles(for: userID, relationship: relationship)
        } catch {
            errorMessage = AppStrings.localized("follow.unavailable")
        }
    }
}
