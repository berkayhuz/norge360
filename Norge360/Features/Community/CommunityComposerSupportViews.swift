import SwiftUI

/// Shared hashtag suggestions for post and comment composers.
struct CommunityHashtagSuggestionList: View {
    let suggestions: [CommunityHashtagSuggestion]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NorgeSpacing.xxs) {
            Text(AppStrings.localized("hashtags.suggestions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion.tag)
                } label: {
                    HStack {
                        Text("#\(suggestion.tag)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: AppStrings.localized("hashtags.usage_count"), suggestion.usageCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("#\(suggestion.tag)")
            }
        }
        .padding(.vertical, NorgeSpacing.xxs)
    }
}

struct EditCommunityPostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore

    let item: CommunityFeedItem
    @State private var draft: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: CommunityFeedItem) {
        self.item = item
        _draft = State(initialValue: item.post.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("feed.your_post")) {
                    TextEditor(text: $draft)
                        .frame(minHeight: 180)
                        .accessibilityLabel(AppStrings.localized("feed.your_post"))
                    Text(
                        String(
                            format: AppStrings.localized("feed.character_count"), draft.count,
                            CommunityContentRules.maximumPostLength)
                    )
                    .font(.caption)
                    .foregroundStyle(draft.count > CommunityContentRules.maximumPostLength ? .red : .secondary)
                }
                Section {
                    Text(AppStrings.localized("post.edit_history_notice"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section {
                        NorgeInlineFeedback(message: errorMessage)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .navigationTitle(AppStrings.localized("post.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("post.save")) { Task { await save() } }
                        .disabled(
                            isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || draft.count > CommunityContentRules.maximumPostLength)
                }
                .norgePlainToolbar()
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await feedStore.updatePost(id: item.post.id, body: draft)
            dismiss()
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error,
                fallbackKey: "feed.error",
                operation: "feed.edit_post"
            )
        }
    }
}

struct EditCommunityCommentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore

    let item: CommunityCommentItem
    let didSave: () async -> Void
    @State private var draft: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: CommunityCommentItem, didSave: @escaping () async -> Void) {
        self.item = item
        self.didSave = didSave
        _draft = State(initialValue: item.comment.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("comments.edit")) {
                    TextEditor(text: $draft)
                        .frame(minHeight: 140)
                    Text(
                        String(
                            format: AppStrings.localized("feed.character_count"), draft.count,
                            CommunityContentRules.maximumCommentLength)
                    )
                    .font(.caption)
                    .foregroundStyle(draft.count > CommunityContentRules.maximumCommentLength ? .red : .secondary)
                }
                if let errorMessage {
                    Section {
                        NorgeInlineFeedback(message: errorMessage)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .navigationTitle(AppStrings.localized("comments.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("post.save")) { Task { await save() } }
                        .disabled(
                            isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || draft.count > CommunityContentRules.maximumCommentLength)
                }
                .norgePlainToolbar()
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await feedStore.updateComment(id: item.comment.id, body: draft)
            await didSave()
            dismiss()
        } catch {
            errorMessage = UserFacingErrorMapper.message(
                for: error,
                fallbackKey: "feed.error",
                operation: "feed.edit_comment"
            )
        }
    }
}
