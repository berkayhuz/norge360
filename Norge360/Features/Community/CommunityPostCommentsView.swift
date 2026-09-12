import SwiftUI

/// Full comment thread, including comment composition and comment-level safety
/// actions. It deliberately owns only a single post's comment state.
struct CommunityPostCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore

    let item: CommunityFeedItem
    @State private var comments: [CommunityCommentItem] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var reportTarget: CommunityCommentItem?
    @State private var blockTarget: CommunityCommentItem?
    @State private var editTarget: CommunityCommentItem?
    @State private var deleteTarget: CommunityCommentItem?
    @StateObject private var hashtagSearchDebouncer = NorgeTaskDebouncer()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NorgeCornerRadius.card) {
                    if isLoading {
                        NorgeLoadingState(minimumHeight: 140)
                    } else if comments.isEmpty {
                        NorgeUnavailableState(
                            AppStrings.localized("comments.empty_title"),
                            systemImage: "bubble.right",
                            description: AppStrings.localized("comments.empty_body")
                        )
                    } else {
                        ForEach(comments) { item in
                            CommunityCommentRow(
                                item: item,
                                canReport: item.comment.authorID != authenticationStore.user?.id,
                                canManage: item.comment.authorID == authenticationStore.user?.id,
                                onEdit: { editTarget = item },
                                onDelete: { deleteTarget = item },
                                onReport: { reportTarget = item },
                                onBlock: { blockTarget = item }
                            )
                            .id(item.id)
                        }
                    }
                }
                .padding(NorgeSpacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.count) { oldCount, newCount in
                if oldCount > 0, newCount > oldCount, let last = comments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color.norgeAppBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { commentComposer }
        .navigationTitle(AppStrings.localized("comments.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    NorgeTopBarActionLabel(systemName: "xmark")
                }
                .accessibilityLabel(AppStrings.localized("feed.cancel"))
            }
            .norgePlainToolbar()
        }
        .task { await loadComments() }
        .refreshable { await loadComments() }
        .onDisappear {
            hashtagSearchDebouncer.cancel()
            feedStore.clearHashtagSuggestions()
        }
        .sheet(item: $editTarget) { item in
            EditCommunityCommentView(item: item) { await loadComments() }
        }
        .confirmationDialog(
            AppStrings.localized("comments.report_title"),
            isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    guard let reportTarget else { return }
                    Task { await feedStore.report(commentID: reportTarget.comment.id, reason: reason) }
                    self.reportTarget = nil
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { reportTarget = nil }
        } message: {
            Text(AppStrings.localized("feed.report_body"))
        }
        .alert(
            AppStrings.localized("feed.block_title"),
            isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
            presenting: blockTarget
        ) { item in
            Button(AppStrings.localized("feed.block_confirm"), role: .destructive) {
                Task { await blockCommentAuthor(item) }
                blockTarget = nil
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { blockTarget = nil }
        } message: { item in
            Text(
                String(
                    format: AppStrings.localized("feed.block_body"),
                    item.author?.displayName ?? AppStrings.localized("feed.member")))
        }
        .alert(
            AppStrings.localized("comments.delete_title"),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { item in
            Button(AppStrings.localized("comments.delete_confirm"), role: .destructive) {
                Task { await deleteComment(item) }
                deleteTarget = nil
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text(AppStrings.localized("comments.delete_body"))
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: NorgeSpacing.extraSmall) {
            if !feedStore.hashtagSuggestions.isEmpty {
                CommunityHashtagSuggestionList(suggestions: feedStore.hashtagSuggestions) { tag in
                    draft = CommunityHashtagRules.replacingActiveHashtag(in: draft, with: tag)
                    feedStore.clearHashtagSuggestions()
                }
            }
            if let errorMessage {
                NorgeInlineFeedback(message: errorMessage)
            }
            if draft.count > CommunityContentRules.maximumCommentLength {
                Text(
                    String(
                        format: AppStrings.localized("feed.character_count"), draft.count,
                        CommunityContentRules.maximumCommentLength)
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(AppStrings.localized("comments.placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .norgeComposerInput(
                        minimumHeight: NorgeControlSize.standard, cornerRadius: 24,
                        horizontalPadding: NorgeSpacing.medium
                    )
                    .accessibilityLabel(AppStrings.localized("comments.placeholder"))
                    .onChange(of: draft) { _, value in
                        hashtagSearchDebouncer.schedule { await feedStore.updateHashtagSuggestions(for: value) }
                    }

                NorgeCircularSendButton(
                    isSending: isSending,
                    isEnabled: canSend,
                    size: NorgeControlSize.standard,
                    iconSize: 21,
                    accessibilityLabel: AppStrings.localized("comments.send")
                ) { Task { await sendComment() } }
            }
        }
        .padding(.horizontal, NorgeSpacing.medium)
        .padding(.vertical, 10)
        .background(Color.norgeAppBackground)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= CommunityContentRules.maximumCommentLength
    }

    private func loadComments() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await feedStore.comments(for: item.post.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendComment() async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await feedStore.addComment(
                to: item.post.id, body: draft.trimmingCharacters(in: .whitespacesAndNewlines))
            draft = ""
            feedStore.clearHashtagSuggestions()
            comments = try await feedStore.comments(for: item.post.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteComment(_ item: CommunityCommentItem) async {
        errorMessage = nil
        do {
            try await feedStore.deleteComment(id: item.comment.id, from: self.item.post.id)
            comments.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func blockCommentAuthor(_ item: CommunityCommentItem) async {
        guard await feedStore.block(authorID: item.comment.authorID) else {
            errorMessage = AppStrings.localized("feed.block_error")
            return
        }
        await loadComments()
    }

}
