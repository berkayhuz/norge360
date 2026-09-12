import SwiftUI

struct CommunityNotificationsView: View {
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore

    var body: some View {
        Group {
            if notificationsStore.isLoading && notificationsStore.items.isEmpty {
                NorgeLoadingState()
            } else if notificationsStore.items.isEmpty {
                NorgeUnavailableState(
                    AppStrings.localized("notifications.empty_title"),
                    systemImage: "bell",
                    description: AppStrings.localized("notifications.empty_body")
                )
            } else {
                List {
                    if let errorMessage = notificationsStore.errorMessage {
                        Section {
                            NorgeInlineFeedback(message: errorMessage)
                        }
                    }

                    ForEach(notificationsStore.items) { item in
                        notificationLink(for: item)
                            .listRowBackground(Color.norgeAppBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await notificationsStore.delete(id: item.id) }
                                } label: {
                                    Label(AppStrings.localized("notifications.delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if item.notification.readAt == nil {
                                    Button {
                                        Task { await notificationsStore.markRead(id: item.id) }
                                    } label: {
                                        Label(AppStrings.localized("notifications.mark_read"), systemImage: "checkmark")
                                    }
                                    .tint(.norgePrimary)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.norgeAppBackground)
        .navigationTitle(AppStrings.localized("notifications.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await notificationsStore.markAllRead() }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .disabled(notificationsStore.unreadCount == 0)
                .accessibilityLabel(AppStrings.localized("notifications.mark_all_read"))
            }.norgePlainToolbar()
        }
        .refreshable { await notificationsStore.reload() }
        .task { await notificationsStore.activate() }
    }

    @ViewBuilder
    private func notificationLink(for item: CommunityNotificationItem) -> some View {
        NavigationLink {
            CommunityNotificationDestinationView(item: item)
        } label: {
            CommunityNotificationRow(item: item)
        }
    }
}

/// Shared by the full notifications list and the foreground toast. One routing
/// surface prevents a banner from reaching a different destination than its
/// corresponding notification row.
struct CommunityNotificationDestinationView: View {
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    let item: CommunityNotificationItem

    var body: some View {
        Group {
            switch item.notification.type {
            case .follow:
                CommunityMemberProfileView(userID: item.notification.actorID)
            case .postLike, .postComment:
                CommunityNotificationPostDestinationView(item: item)
            case .groupJoinApproved, .groupJoinRejected:
                NotificationGroupDestinationView(item: item)
            case .groupInvitation:
                NotificationGroupDestinationView(item: item)
            case .messageRequest:
                CommunityConversationsView()
            case .directMessage:
                NotificationConversationDestinationView(item: item)
            case .eventUpdated, .eventReminder:
                CommunityEventsView()
            case .eventInvitation:
                CommunityEventsView(focusedEventID: item.notification.eventID)
            case .moderationContentRemoved, .moderationContentRestored,
                .moderationMemberRestricted, .moderationMemberRestrictionRevoked:
                ModerationNotificationDestinationView(item: item)
            }
        }
        .task { await notificationsStore.markRead(id: item.id) }
    }
}

struct CommunityNotificationToast: View {
    let item: CommunityNotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CommunityAvatarView(url: item.actor?.avatarURL, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Color.norgeTopBarBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.norgeTopBarBackground.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let actorName = item.actor?.displayName ?? AppStrings.localized("feed.member")
        return switch item.notification.type {
        case .follow:
            String(format: AppStrings.localized("notifications.follow"), actorName)
        case .postLike:
            String(format: AppStrings.localized("notifications.post_like"), actorName)
        case .postComment:
            String(format: AppStrings.localized("notifications.post_comment"), actorName)
        case .groupJoinApproved:
            AppStrings.localized("notifications.group_join_approved")
        case .groupJoinRejected:
            AppStrings.localized("notifications.group_join_rejected")
        case .groupInvitation:
            AppStrings.localized("notifications.group_invitation")
        case .messageRequest:
            AppStrings.localized("notifications.message_request")
        case .directMessage:
            actorName
        case .eventUpdated:
            AppStrings.localized("notifications.event_updated")
        case .eventReminder:
            AppStrings.localized("notifications.event_reminder")
        case .eventInvitation:
            AppStrings.localized("notifications.event_invitation")
        case .moderationContentRemoved:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_removed")
        case .moderationContentRestored:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_restored")
        case .moderationMemberRestricted:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restricted")
        case .moderationMemberRestrictionRevoked:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restriction_revoked")
        }
    }

    private var subtitle: String {
        switch item.notification.type {
        case .directMessage:
            item.notification.body ?? AppStrings.localized("notifications.direct_message")
        default:
            AppStrings.localized("notifications.open_hint")
        }
    }
}

private struct CommunityNotificationRow: View {
    let item: CommunityNotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CommunityAvatarView(url: item.actor?.avatarURL, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(relativeDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if item.notification.readAt == nil {
                Circle()
                    .fill(Color.norgePrimary)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(AppStrings.localized("notifications.unread"))
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var actorName: String {
        item.actor?.displayName ?? AppStrings.localized("feed.member")
    }

    private var message: String {
        switch item.notification.type {
        case .follow:
            String(format: AppStrings.localized("notifications.follow"), actorName)
        case .postLike:
            String(format: AppStrings.localized("notifications.post_like"), actorName)
        case .postComment:
            String(format: AppStrings.localized("notifications.post_comment"), actorName)
        case .groupJoinApproved:
            AppStrings.localized("notifications.group_join_approved")
        case .groupJoinRejected:
            AppStrings.localized("notifications.group_join_rejected")
        case .groupInvitation:
            AppStrings.localized("notifications.group_invitation")
        case .messageRequest:
            AppStrings.localized("notifications.message_request")
        case .directMessage:
            directMessageText
        case .eventUpdated:
            AppStrings.localized("notifications.event_updated")
        case .eventReminder:
            AppStrings.localized("notifications.event_reminder")
        case .eventInvitation:
            AppStrings.localized("notifications.event_invitation")
        case .moderationContentRemoved:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_removed")
        case .moderationContentRestored:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_restored")
        case .moderationMemberRestricted:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restricted")
        case .moderationMemberRestrictionRevoked:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restriction_revoked")
        }
    }

    private var directMessageText: String {
        guard let preview = item.notification.body, !preview.isEmpty else {
            return String(format: AppStrings.localized("notifications.direct_message_from"), actorName)
        }
        return "\(actorName): \(preview)"
    }

    private var relativeDate: String {
        Self.dateFormatter.localizedString(for: item.notification.createdAt, relativeTo: .now)
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct NotificationConversationDestinationView: View {
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    let item: CommunityNotificationItem
    @State private var conversation: CommunityConversationSummary?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState()
            } else if let conversation {
                CommunityConversationDetailView(conversation: conversation)
            } else {
                NorgeUnavailableState(
                    AppStrings.localized("messages.empty_title"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: AppStrings.localized("notifications.message_unavailable_body")
                )
            }
        }
        .task {
            await notificationsStore.markRead(id: item.id)
            await conversationsStore.reload()
            conversation = item.notification.conversationID.flatMap { id in
                conversationsStore.conversations.first(where: { $0.id == id && $0.status == .active })
            }
            isLoading = false
        }
    }
}

private struct ModerationNotificationDestinationView: View {
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    let item: CommunityNotificationItem

    var body: some View {
        NorgeUnavailableState(
            message,
            systemImage: "checkmark.shield",
            description: AppStrings.localized("guidelines.reports_body")
        )
        .task { await notificationsStore.markRead(id: item.id) }
    }

    private var message: String {
        switch item.notification.type {
        case .moderationContentRemoved:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_removed")
        case .moderationContentRestored:
            item.notification.body ?? AppStrings.localized("notifications.moderation_content_restored")
        case .moderationMemberRestricted:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restricted")
        case .moderationMemberRestrictionRevoked:
            item.notification.body ?? AppStrings.localized("notifications.moderation_member_restriction_revoked")
        default:
            AppStrings.localized("notifications.title")
        }
    }
}

private struct NotificationGroupDestinationView: View {
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    let item: CommunityNotificationItem

    var body: some View {
        Group {
            if let groupID = item.notification.groupID,
                let group = groupsStore.groups.first(where: { $0.id == groupID })
            {
                CommunityGroupDetailView(group: group)
            } else {
                NorgeUnavailableState(
                    AppStrings.localized("notifications.group_unavailable_title"),
                    systemImage: "person.3",
                    description: AppStrings.localized("notifications.group_unavailable_body")
                )
            }
        }
        .task {
            await notificationsStore.markRead(id: item.id)
            await groupsStore.reload()
        }
    }
}

private struct CommunityNotificationPostDestinationView: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore

    let item: CommunityNotificationItem
    @State private var post: CommunityFeedItem?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState()
            } else if let post {
                CommunityCommentsView(item: post)
            } else {
                NorgeUnavailableState(
                    AppStrings.localized("notifications.post_unavailable_title"),
                    systemImage: "rectangle.stack.badge.questionmark",
                    description: AppStrings.localized("notifications.post_unavailable_body")
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        await notificationsStore.markRead(id: item.id)
        guard let postID = item.notification.postID else { return }
        post = try? await feedStore.post(id: postID)
    }
}
