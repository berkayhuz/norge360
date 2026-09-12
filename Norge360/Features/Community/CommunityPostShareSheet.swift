import SwiftUI

/// Recipient selection and delivery for a shared community post. Kept outside
/// the feed renderer so feed layout changes do not alter messaging behavior.
struct CommunityPostShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    let item: CommunityFeedItem
    @State private var query = ""
    @State private var selectedRecipientIDs: Set<UUID> = []
    @FocusState private var isSearchFocused: Bool
    @State private var isSending = false
    @State private var errorMessage: String?

    private var suggestedProfiles: [CommunityProfile] {
        var seen = Set<UUID>()
        return feedStore.items.compactMap(\.author).filter { profile in
            profile.isPublic
                && profile.userID != authenticationStore.user?.id
                && seen.insert(profile.userID).inserted
        }
    }

    private var profiles: [CommunityProfile] {
        let source =
            query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            ? searchStore.results.profiles
            : suggestedProfiles
        return
            source
            .filter { $0.isPublic && $0.userID != authenticationStore.user?.id }
            .sorted { lhs, rhs in
                let lhsIsSelected = selectedRecipientIDs.contains(lhs.userID)
                let rhsIsSelected = selectedRecipientIDs.contains(rhs.userID)
                if lhsIsSelected != rhsIsSelected { return lhsIsSelected }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: NorgeCornerRadius.card), count: 3)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: NorgeSpacing.medium) {
                Text(AppStrings.localized("feed.share_intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, NorgeSpacing.large)

                TextField(AppStrings.localized("feed.share_search"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .padding(.horizontal, NorgeSpacing.medium)
                    .frame(height: NorgeControlSize.standard)
                    .background(Color.norgeInputSurface, in: Capsule())
                    .padding(.horizontal, NorgeSpacing.large)

                if let errorMessage {
                    NorgeInlineFeedback(message: errorMessage)
                        .padding(.horizontal, NorgeSpacing.large)
                }

                if searchStore.isSearching {
                    NorgeLoadingState(minimumHeight: 200)
                } else if profiles.isEmpty {
                    NorgeUnavailableState(
                        AppStrings.localized("feed.share_empty"), systemImage: "person.crop.circle.badge.question")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: NorgeSpacing.large) {
                            ForEach(profiles) { profile in
                                Button {
                                    toggleSelection(profile.userID)
                                } label: {
                                    VStack(spacing: 7) {
                                        ZStack(alignment: .bottomTrailing) {
                                            CommunityAvatarView(url: profile.avatarURL, size: 74)
                                            if selectedRecipientIDs.contains(profile.userID) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.norgePrimary, .white)
                                                    .font(.title3)
                                            }
                                        }
                                        Text(profile.displayName)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(profile.displayName)
                            }
                        }
                        .padding(.horizontal, NorgeSpacing.large)
                        .padding(.bottom, NorgeSpacing.medium)
                    }
                }
            }
            .padding(.top, NorgeSpacing.small - 2)
            .background {
                Color.norgeAppBackground
                    .contentShape(Rectangle())
                    .onTapGesture { isSearchFocused = false }
            }
            .navigationTitle(AppStrings.localized("feed.share_post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("feed.share")) { Task { await share() } }
                        .disabled(selectedRecipientIDs.isEmpty || isSending)
                }
            }
            .task(id: query) {
                guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
                    searchStore.clear()
                    return
                }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                await searchStore.search(query: query)
            }
        }
    }

    private func toggleSelection(_ userID: UUID) {
        if selectedRecipientIDs.contains(userID) {
            selectedRecipientIDs.remove(userID)
        } else {
            selectedRecipientIDs.insert(userID)
        }
    }

    private func share() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let activeConversations = Dictionary(
            conversationsStore.conversations
                .filter { $0.status == .active }
                .map { ($0.otherUserID, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let body = String(
            format: AppStrings.localized("feed.shared_post_message"), String(item.post.body.prefix(1_700)))
        var sentCount = 0
        for recipientID in selectedRecipientIDs {
            guard let conversationID = activeConversations[recipientID] else { continue }
            do {
                try await conversationsStore.send(conversationID: conversationID, body: body)
                sentCount += 1
            } catch {
                continue
            }
        }
        if sentCount > 0 { dismiss() } else { errorMessage = AppStrings.localized("feed.share_requires_conversation") }
    }
}
