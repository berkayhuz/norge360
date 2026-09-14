import SwiftUI

struct CommunityFullscreenPostDetails: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let context: CommunityFullscreenPostContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                CommunityAvatarView(url: context.item.author?.avatarURL, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.item.author?.displayName ?? AppStrings.localized("feed.member"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let username = context.item.author?.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if context.showsAuthorFollowAction,
                    !context.isCurrentUser,
                    context.isAuthorFollowStateLoaded,
                    !context.isAuthorFollowed
                {
                    Button(action: context.onFollowAuthor) {
                        if context.isFollowingAuthor {
                            ProgressView().tint(.white)
                        } else {
                            Text(AppStrings.localized("follow.follow"))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Color.norgePrimary, in: Capsule())
                    .disabled(context.isFollowingAuthor)
                }
            }

            Text(context.item.post.body)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)

            HStack(spacing: 12) {
                Button(action: context.onToggleLike) {
                    fullscreenActionLabel(
                        context.item.likesCount,
                        symbol: context.item.isLikedByCurrentUser ? "heart.fill" : "heart"
                    )
                }
                .foregroundStyle(context.item.isLikedByCurrentUser ? Color.red : actionForeground)
                .disabled(context.isLiking)

                Button {
                    dismissThen(context.onOpenComments)
                } label: {
                    fullscreenActionLabel(context.item.commentsCount, symbol: "bubble.right")
                }
                .foregroundStyle(actionForeground)

                ShareLink(item: context.postURL) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(actionForeground)
                .accessibilityLabel(AppStrings.localized("feed.share_post"))

                Spacer(minLength: 0)

                Button(action: context.onToggleSave) {
                    Image(systemName: context.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(context.isSaved ? Color.norgePrimary : actionForeground)
                .disabled(context.isSaving)
            }

            Button {
                dismissThen(context.onOpenComments)
            } label: {
                HStack {
                    Text(AppStrings.localized("media.comment_placeholder"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(Color.norgeInputSurface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("comments.open"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.norgeTopBarBackground)
    }

    private func fullscreenActionLabel(_ count: Int, symbol: String) -> some View {
        HStack(spacing: count > 0 ? 3 : 0) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(minWidth: 40, minHeight: 40)
        .contentShape(Rectangle())
    }

    private var actionForeground: Color {
        colorScheme == .dark ? .white : .secondary
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }
}
