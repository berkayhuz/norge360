import SwiftUI

/// A single comment with its author navigation and owner/moderation actions.
struct CommunityCommentRow: View {
    let item: CommunityCommentItem
    let canReport: Bool
    let canManage: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                CommunityMemberProfileView(userID: item.comment.authorID)
            } label: {
                CommunityAvatarView(url: item.author?.avatarURL, size: 36)
                    .frame(minWidth: NorgeControlSize.tapTarget, minHeight: NorgeControlSize.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.author?.displayName ?? AppStrings.localized("feed.member"))
            .accessibilityHint(AppStrings.localized("member.open_profile"))
            VStack(alignment: .leading, spacing: NorgeSpacing.xxs) {
                NavigationLink {
                    CommunityMemberProfileView(userID: item.comment.authorID)
                } label: {
                    Text(item.author?.displayName ?? AppStrings.localized("feed.member"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("member.open_profile"))
                Text(item.comment.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.relativeDateFormatter.localizedString(for: item.comment.createdAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if canReport || canManage {
                Menu {
                    if canManage {
                        Button(AppStrings.localized("comments.edit"), systemImage: "pencil") {
                            onEdit()
                        }
                        Button(AppStrings.localized("comments.delete"), systemImage: "trash", role: .destructive) {
                            onDelete()
                        }
                    }
                    if canReport {
                        Button(AppStrings.localized("feed.report"), systemImage: "exclamationmark.bubble") {
                            onReport()
                        }
                        Button(AppStrings.localized("feed.block"), systemImage: "hand.raised", role: .destructive) {
                            onBlock()
                        }
                    }
                } label: {
                    NorgeOverflowMenuLabel()
                }
                .accessibilityLabel(AppStrings.localized("feed.post_actions"))
            }
        }
        .padding(.vertical, NorgeSpacing.xxs)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
