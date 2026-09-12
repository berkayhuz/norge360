import PhotosUI
import SwiftUI

// The feed screen keeps composer, media-editor and feed lifecycle code together
// so their cancellation and upload state transitions remain local.
// swiftlint:disable file_length

struct CommunityFeedView: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var followStore: CommunityFollowStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore

    @State private var isPresentingComposer = false
    @State private var isHeaderVisible = true
    @State private var feedFilter: FeedFilter = .forYou
    @State private var followedMemberIDs: Set<UUID> = []
    @State private var forYouRefreshToken = Int.random(in: 1...Int.max)

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollHeaderVisibilityObserver { visible in
                    guard isHeaderVisible != visible else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        isHeaderVisible = visible
                    }
                }
                .frame(height: 0)

                LazyVStack(alignment: .leading, spacing: NorgeLayoutMetrics.feedItemSpacing) {
                    if let errorMessage = feedStore.errorMessage {
                        NorgeInlineFeedback(message: errorMessage)
                    }
                    if let noticeMessage = feedStore.noticeMessage {
                        NorgeInlineFeedback(message: noticeMessage, kind: .notice)
                    }

                    if feedStore.isLoading && feedStore.items.isEmpty {
                        NorgeLoadingState(minimumHeight: 240)
                    } else if feedStore.items.isEmpty {
                        NorgeUnavailableState(
                            AppStrings.localized("feed.empty_title"),
                            systemImage: "rectangle.stack",
                            description: AppStrings.localized("feed.empty_body")
                        )
                    } else {
                        CommunityEventFeedRail(
                            items: eventsStore.prioritizedItems(for: communityProfileStore.profile?.cityOrRegion))
                        ForEach(displayedItems) { item in
                            CommunityFeedPostView(item: item)
                                .onAppear {
                                    loadMoreIfNeeded(afterDisplaying: item, in: displayedItems)
                                }
                        }

                        if feedStore.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else if !feedStore.canLoadMore && feedFilter != .follows {
                            Label(AppStrings.localized("feed.end"), systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                }
                .padding(.horizontal, NorgeSpacing.medium)
                .padding(.top, NorgeSpacing.medium)
                .padding(.bottom, NorgeSpacing.large)
            }
            .background(Color.norgeAppBackground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isHeaderVisible {
                    NorgeTopBar {
                        ZStack {
                            HStack(spacing: NorgeTopBarMetrics.itemSpacing) {
                                Button {
                                    isPresentingComposer = true
                                } label: {
                                    NorgeTopBarActionLabel(systemName: "plus")
                                }
                                .accessibilityLabel(AppStrings.localized("feed.compose"))
                                .accessibilityHint(AppStrings.localized("feed.compose_hint"))

                                Spacer()

                                NavigationLink {
                                    CommunityNotificationsView()
                                } label: {
                                    NorgeTopBarActionLabel(
                                        systemName: "bell",
                                        badgeText: notificationsStore.unreadCount > 0 ? notificationBadgeText : nil
                                    )
                                }
                                .accessibilityLabel(AppStrings.localized("notifications.title"))
                                .accessibilityValue(notificationAccessibilityValue)
                                .accessibilityHint(AppStrings.localized("notifications.open_hint"))
                            }

                            Menu {
                                ForEach(FeedFilter.allCases) { filter in
                                    Button(filter.title, systemImage: feedFilter == filter ? "checkmark" : "circle") {
                                        feedFilter = filter
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(feedFilter.title)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppStrings.localized("feed.filter"))
                            .accessibilityValue(feedFilter.title)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isHeaderVisible)
            .refreshable {
                forYouRefreshToken &+= 1
                await feedStore.refreshIfNeeded()
            }
            .task {
                await feedStore.activate()
                await groupsStore.activate()
                await eventsStore.activate()
                await notificationsStore.activate()
            }
            .task(id: feedFilter) {
                guard feedFilter == .follows,
                    let userID = authenticationStore.user?.id
                else { return }
                do {
                    let profiles = try await followStore.profiles(for: userID, relationship: .following)
                    followedMemberIDs = Set(profiles.map(\.userID))
                } catch {
                    // The normal feed remains available if followed profiles cannot load.
                    followedMemberIDs = []
                }
            }
            .sheet(isPresented: $isPresentingComposer) {
                CreateCommunityPostView(
                    joinedGroups: groupsStore.groups.filter { groupsStore.joinedGroupIDs.contains($0.id) }
                )
            }
        }
    }

    private var notificationBadgeText: String {
        notificationsStore.unreadCount > 9 ? "9+" : String(notificationsStore.unreadCount)
    }

    private var notificationAccessibilityValue: String {
        guard notificationsStore.unreadCount > 0 else {
            return AppStrings.localized("notifications.none_unread")
        }
        return String(format: AppStrings.localized("notifications.unread_count"), notificationsStore.unreadCount)
    }

    /// Starts the next request only after the member has actually reached the
    /// tail of the current page. This avoids eager sentinel creation that can
    /// otherwise load several pages while the screen is first appearing.
    private func loadMoreIfNeeded(afterDisplaying item: CommunityFeedItem, in items: [CommunityFeedItem]) {
        guard feedStore.canLoadMore,
            let triggerID = items.dropLast(2).last?.id,
            item.id == triggerID
        else { return }
        Task { await feedStore.loadMore() }
    }

    private var displayedItems: [CommunityFeedItem] {
        switch feedFilter {
        case .forYou:
            return CommunityDiscoveryRules.forYouPosts(
                from: feedStore.items,
                joinedGroupIDs: groupsStore.joinedGroupIDs,
                surface: .home,
                refreshToken: forYouRefreshToken
            )
        case .latest:
            return CommunityDiscoveryRules.latestPosts(from: feedStore.items)
        case .follows:
            let followedPosts = CommunityDiscoveryRules.latestPosts(
                from: feedStore.items.filter { followedMemberIDs.contains($0.post.authorID) }
            )
            let publicFallback = CommunityDiscoveryRules.forYouPosts(
                from: feedStore.items.filter { !followedMemberIDs.contains($0.post.authorID) },
                joinedGroupIDs: groupsStore.joinedGroupIDs,
                surface: .home,
                refreshToken: forYouRefreshToken
            )
            // Follows prioritizes followed members without becoming an empty or
            // terminal feed when a member has not followed anyone yet.
            return followedPosts + publicFallback
        }
    }
}

struct CommunityEventFeedRail: View {
    let items: [CommunityEventItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(AppStrings.localized("feed.upcoming_events"), systemImage: "calendar")
                    .font(.headline)
                ForEach(items.prefix(2)) { item in
                    NavigationLink {
                        CommunityEventsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Label(
                                item.event.startsAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "calendar"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            Label(item.event.areaLabel, systemImage: "mappin.and.ellipse")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.norgeInputSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
        }
    }
}

private enum FeedFilter: CaseIterable, Identifiable, Hashable {
    case forYou
    case latest
    case follows

    var id: Self { self }

    var title: String {
        switch self {
        case .forYou: AppStrings.localized("explore.relevant")
        case .latest: AppStrings.localized("explore.latest")
        case .follows: AppStrings.localized("feed.follows")
        }
    }
}

/// Shared by Home, Explore and member profiles. Render in a stack rather than
/// a List row: the author and the post are independent navigation targets.
struct CommunityFeedPostView: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var followStore: CommunityFollowStore

    let item: CommunityFeedItem
    var isDetail = false
    var showsAuthorFollowAction = true
    @State private var currentItem: CommunityFeedItem
    @State private var isRemoved = false
    @State private var isShowingComments = false
    @State private var isEditing = false
    @State private var isShowingHistory = false
    @State private var isReporting = false
    @State private var isBlocking = false
    @State private var isDeleting = false
    @State private var isWorking = false
    @State private var feedbackMessage: String?
    @State private var hasError = false
    @State private var isPresentingShare = false

    init(item: CommunityFeedItem, isDetail: Bool = false, showsAuthorFollowAction: Bool = true) {
        self.item = item
        self.isDetail = isDetail
        self.showsAuthorFollowAction = showsAuthorFollowAction
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        Group {
            if !isRemoved {
                VStack(alignment: .leading, spacing: 8) {
                    postRow
                    if let feedbackMessage {
                        NorgeInlineFeedback(message: feedbackMessage, kind: hasError ? .error : .notice)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            } else if isDetail {
                NorgeUnavailableState(
                    AppStrings.localized("post_detail.unavailable"),
                    systemImage: "text.bubble",
                    description: AppStrings.localized("post_detail.unavailable_body")
                )
            }
        }
        .sheet(isPresented: $isShowingComments, onDismiss: refreshAfterSheet) {
            NavigationStack {
                CommunityPostCommentsView(item: currentItem)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.norgeAppBackground)
        }
        .sheet(isPresented: $isEditing, onDismiss: refreshAfterSheet) {
            EditCommunityPostView(item: currentItem)
        }
        .sheet(isPresented: $isShowingHistory) {
            CommunityPostEditHistoryView(postID: currentItem.id)
        }
        .sheet(isPresented: $isPresentingShare) {
            CommunityPostShareSheet(item: currentItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.norgeAppBackground)
        }
        .confirmationDialog(
            AppStrings.localized("feed.report_title"),
            isPresented: $isReporting,
            titleVisibility: .visible
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    Task {
                        await feedStore.report(postID: currentItem.id, reason: reason)
                        feedbackMessage = feedStore.noticeMessage ?? feedStore.errorMessage
                        hasError = feedStore.noticeMessage == nil
                    }
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("feed.report_body"))
        }
        .alert(AppStrings.localized("feed.block_title"), isPresented: $isBlocking) {
            Button(AppStrings.localized("feed.block_confirm"), role: .destructive) {
                Task {
                    if await feedStore.block(authorID: currentItem.post.authorID) {
                        isRemoved = true
                    } else {
                        feedbackMessage = feedStore.errorMessage
                        hasError = true
                    }
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: AppStrings.localized("feed.block_body"),
                    currentItem.author?.displayName ?? AppStrings.localized("feed.member")))
        }
        .alert(AppStrings.localized("post.delete_title"), isPresented: $isDeleting) {
            Button(AppStrings.localized("post.delete_confirm"), role: .destructive) {
                Task {
                    await feedStore.deletePost(id: currentItem.id)
                    if let error = feedStore.errorMessage {
                        feedbackMessage = error
                        hasError = true
                    } else {
                        isRemoved = true
                    }
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("post.delete_body"))
        }
        .task {
            if isDetail { await refreshPost() }
        }
        .task(id: currentItem.post.authorID) {
            if showsAuthorFollowAction { await loadAuthorFollowState() }
        }
        .onChange(of: item) { _, updatedItem in currentItem = updatedItem }
        .onChange(of: feedStore.items) { _, items in
            if let updated = items.first(where: { $0.id == currentItem.id }) {
                currentItem = updated
            }
        }
    }

    private var postRow: some View {
        CommunityPostRow(
            item: currentItem,
            group: groupsStore.groups.first { $0.id == currentItem.post.groupID },
            isDetail: isDetail,
            isCurrentUser: currentItem.post.authorID == authenticationStore.user?.id,
            isLiking: isWorking || feedStore.likingPostIDs.contains(currentItem.id),
            showsAuthorFollowAction: showsAuthorFollowAction,
            isAuthorFollowed: followStore.states[currentItem.post.authorID]?.isFollowing == true,
            isAuthorFollowStateLoaded: followStore.loadedUserIDs.contains(currentItem.post.authorID),
            isFollowingAuthor: followStore.updatingUserIDs.contains(currentItem.post.authorID),
            onToggleLike: { Task { await toggleLike() } },
            onFollowAuthor: { Task { await followAuthor() } },
            onOpenComments: { isShowingComments = true },
            onEdit: { isEditing = true },
            onDelete: { isDeleting = true },
            onShowEditHistory: { isShowingHistory = true },
            onReport: { isReporting = true },
            onBlock: { isBlocking = true },
            onShare: { isPresentingShare = true }
        )
    }

    private func toggleLike() async {
        isWorking = true
        defer { isWorking = false }
        await feedStore.toggleLike(postID: currentItem.id)
        if let error = feedStore.errorMessage {
            feedbackMessage = error
            hasError = true
        } else {
            feedbackMessage = nil
            await refreshPost()
        }
    }

    private func refreshAfterSheet() {
        Task { await refreshPost() }
    }

    private func refreshPost() async {
        do {
            if let updated = try await feedStore.post(id: currentItem.id) {
                currentItem = updated
            } else {
                isRemoved = true
            }
        } catch is CancellationError {
            return
        } catch {
            feedbackMessage = error.localizedDescription
            hasError = true
        }
    }

    private func loadAuthorFollowState() async {
        guard let currentUserID = authenticationStore.user?.id else { return }
        guard currentItem.post.authorID != currentUserID else { return }
        try? await followStore.loadState(for: currentItem.post.authorID)
    }

    private func followAuthor() async {
        guard let currentUserID = authenticationStore.user?.id,
            currentItem.post.authorID != currentUserID
        else { return }
        feedbackMessage = nil
        hasError = false
        do {
            try await followStore.toggleFollow(for: currentItem.post.authorID)
        } catch {
            feedbackMessage = AppStrings.localized("follow.error")
            hasError = true
        }
    }
}

struct CommunityPostDetailView: View {
    let item: CommunityFeedItem
    let showsAuthorFollowAction: Bool
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @State private var currentItem: CommunityFeedItem

    init(item: CommunityFeedItem, showsAuthorFollowAction: Bool = true) {
        self.item = item
        self.showsAuthorFollowAction = showsAuthorFollowAction
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            CommunityFeedPostView(
                item: currentItem,
                isDetail: true,
                showsAuthorFollowAction: showsAuthorFollowAction
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color.norgeAppBackground)
        .navigationTitle(AppStrings.localized("post_detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await refreshPost() }
        .task { await refreshPost() }
    }

    private func refreshPost() async {
        if let updated = try? await feedStore.post(id: item.id) { currentItem = updated }
    }
}

// Older deep-link destinations now land on the post. Comments are presented
// separately from its action bar, preserving a single back-stack entry.
typealias CommunityCommentsView = CommunityPostDetailView

private struct CommunityPostRow: View {  // swiftlint:disable:this type_body_length
    @EnvironmentObject private var tabRouter: AppTabRouter
    let item: CommunityFeedItem
    let group: CommunityGroup?
    let isDetail: Bool
    let isCurrentUser: Bool
    let isLiking: Bool
    let showsAuthorFollowAction: Bool
    let isAuthorFollowed: Bool
    let isAuthorFollowStateLoaded: Bool
    let isFollowingAuthor: Bool
    let onToggleLike: () -> Void
    let onFollowAuthor: () -> Void
    let onOpenComments: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShowEditHistory: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onShare: () -> Void
    @State private var isShowingWhyThisPost = false
    @State private var isPostExpanded = false
    @State private var previewProfile: CommunityProfile?
    @State private var suppressProfileOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if isCurrentUser {
                        Button(action: openAuthorProfile) {
                            authorProfileLabel
                        }
                    } else {
                        NavigationLink {
                            CommunityMemberProfileView(userID: item.post.authorID)
                        } label: {
                            authorProfileLabel
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("member.open_profile"))
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            suppressProfileOpen = true
                            previewProfile = item.author
                            Task {
                                try? await Task.sleep(for: .milliseconds(450))
                                suppressProfileOpen = false
                            }
                        }
                )
                .popover(item: $previewProfile, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) { profile in
                    Group {
                        if isCurrentUser {
                            Button {
                                previewProfile = nil
                                open(profile.userID)
                            } label: {
                                CommunityProfileQuickPreview(profile: profile)
                            }
                        } else {
                            NavigationLink {
                                CommunityMemberProfileView(userID: profile.userID)
                            } label: {
                                CommunityProfileQuickPreview(profile: profile)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .presentationCompactAdaptation(.popover)
                }

                if showsAuthorFollowAction && !isCurrentUser && isAuthorFollowStateLoaded && !isAuthorFollowed {
                    Button(action: onFollowAuthor) {
                        if isFollowingAuthor {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label(
                                AppStrings.localized("follow.follow"),
                                systemImage: "person.badge.plus"
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(Color.norgePrimary, in: Capsule())
                    .disabled(isFollowingAuthor)
                    .accessibilityLabel(AppStrings.localized("follow.follow"))
                }

                Menu {
                    if !isCurrentUser {
                        Button(AppStrings.localized("feed.why_this_post"), systemImage: "sparkles") {
                            isShowingWhyThisPost = true
                        }
                    }
                    if isCurrentUser {
                        Button(AppStrings.localized("post.edit"), systemImage: "pencil", action: onEdit)
                        Button(
                            AppStrings.localized("post.delete"), systemImage: "trash", role: .destructive,
                            action: onDelete)
                    } else {
                        Button(
                            AppStrings.localized("feed.report"), systemImage: "exclamationmark.bubble", action: onReport
                        )
                        Button(
                            AppStrings.localized("feed.block"), systemImage: "hand.raised", role: .destructive,
                            action: onBlock)
                    }
                } label: {
                    NorgeOverflowMenuLabel(font: .title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("feed.post_actions"))
            }

            if isDetail {
                postText
                    .textSelection(.enabled)
                postMedia
            } else {
                NavigationLink {
                    CommunityPostDetailView(item: item, showsAuthorFollowAction: showsAuthorFollowAction)
                } label: {
                    postText
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("post_detail.open"))
                postMedia
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { postContext }
                VStack(alignment: .leading, spacing: 5) { postContext }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            if item.editHistoryCount > 0 {
                Button(AppStrings.localized("post.edited"), action: onShowEditHistory)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                    .accessibilityHint(AppStrings.localized("post.edit_history_hint"))
            }

            HStack(spacing: 0) {
                Button(action: onToggleLike) {
                    compactLabel("\(item.likesCount)", symbol: item.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .foregroundStyle(item.isLikedByCurrentUser ? Color.red : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLiking)
                .accessibilityLabel(
                    item.isLikedByCurrentUser ? AppStrings.localized("likes.remove") : AppStrings.localized("likes.add")
                )
                .accessibilityValue(String(format: AppStrings.localized("likes.count"), item.likesCount))

                Button(action: onOpenComments) {
                    compactLabel("\(item.commentsCount)", symbol: "bubble.right")
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(AppStrings.localized("comments.open"))
                .accessibilityValue(String(format: AppStrings.localized("comments.count"), item.commentsCount))

                Button(action: onShare) {
                    Image(systemName: "paperplane")
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(AppStrings.localized("feed.share_post"))
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.top, -12)

            if isDetail {
                Text(item.post.createdAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppStrings.localized("post_detail.community_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .alert(AppStrings.localized("feed.why_this_post"), isPresented: $isShowingWhyThisPost) {
            Button(AppStrings.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(whyThisPostMessage)
        }
    }

    private func openAuthorProfile() {
        guard !suppressProfileOpen else { return }
        tabRouter.openProfile(item.post.authorID)
    }

    private func open(_ userID: UUID) {
        tabRouter.openProfile(userID)
    }

    private var authorProfileLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            CommunityAvatarView(url: item.author?.avatarURL, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.author?.displayName ?? AppStrings.localized("feed.member"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let username = item.author?.username, !username.isEmpty {
                        Text("@\(username)").lineLimit(1)
                        Text("·")
                    }
                    Text(timestamp(for: item.post.createdAt)).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var postText: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = item.post.title, !title.isEmpty {
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            Text(item.post.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(isPostExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if !isPostExpanded && item.post.body.count > 180 {
                Button(AppStrings.localized("feed.more")) {
                    withAnimation(.easeInOut(duration: 0.16)) { isPostExpanded = true }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.norgePrimary)
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("feed.show_more_accessibility"))
            }
        }
    }

    @ViewBuilder private var postMedia: some View {
        if !item.media.isEmpty {
            CommunityPostMediaCarousel(media: item.media)
        }
    }

    @ViewBuilder
    private var postContext: some View {
        compactLabel(AppStrings.localized("feed.kind.\(item.post.kind.rawValue)"), symbol: kindSymbol(item.post.kind))
        if let group {
            compactLabel(group.name, symbol: "person.3")
        } else {
            compactLabel(AppStrings.localized("feed.general"), symbol: "globe.europe.africa")
        }
    }

    private func timestamp(for date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }

    private func kindSymbol(_ kind: CommunityPostKind) -> String {
        switch kind {
        case .update: "text.bubble"
        case .question: "questionmark.bubble"
        case .recommendation: "hand.thumbsup"
        }
    }

    private func compactLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
        }
    }

    private var whyThisPostMessage: String {
        if isAuthorFollowed, let username = item.author?.username {
            return String(format: AppStrings.localized("feed.why_following"), "@\(username)")
        }
        if let group {
            return String(format: AppStrings.localized("feed.why_group"), group.name)
        }
        return AppStrings.localized("feed.why_relevant")
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

// The composer intentionally keeps audience, content, media and publication
// state together so a failed upload preserves the user's local draft.
// swiftlint:disable:next type_body_length
struct CreateCommunityPostView: View {
    enum Destination: Hashable, Identifiable {
        case general
        case group(UUID)

        var id: String {
            switch self {
            case .general: "general"
            case .group(let id): id.uuidString
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore

    let joinedGroups: [CommunityGroup]
    @State private var draftBody = ""
    @State private var draftTitle = ""
    @State private var kind: CommunityPostKind = .update
    @State private var destination: Destination = .general
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var preparedImages: [CommunityImageUpload] = []
    @State private var imageEditorDraft: CommunityImageDraft?
    @State private var queuedImageDrafts: [CommunityImageDraft] = []
    @State private var editingImageIndex: Int?
    @State private var isLoadingPhotos = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var mediaErrorMessage: String?
    @StateObject private var hashtagSearchDebouncer = NorgeTaskDebouncer()

    init(joinedGroups: [CommunityGroup], initialDestination: Destination = .general) {
        self.joinedGroups = joinedGroups
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("feed.audience")) {
                    Picker(AppStrings.localized("feed.share_to"), selection: $destination) {
                        Text(AppStrings.localized("feed.general"))
                            .tag(Destination.general)
                        ForEach(joinedGroups) { group in
                            Text(group.name)
                                .tag(Destination.group(group.id))
                        }
                    }

                    if joinedGroups.isEmpty {
                        Text(AppStrings.localized("feed.join_group_note"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(AppStrings.localized("feed.post_type")) {
                    Picker(AppStrings.localized("feed.post_type"), selection: $kind) {
                        ForEach(CommunityPostKind.allCases) { kind in
                            Text(kindTitle(kind))
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(AppStrings.localized("feed.your_post")) {
                    TextField(AppStrings.localized("feed.post_title"), text: $draftTitle)
                        .lineLimit(1)
                        .onChange(of: draftTitle) { _, value in
                            if value.count > CommunityContentRules.maximumPostTitleLength {
                                draftTitle = String(value.prefix(CommunityContentRules.maximumPostTitleLength))
                            }
                        }
                    ZStack(alignment: .topLeading) {
                        if draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(AppStrings.localized("feed.post_description_optional"))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $draftBody)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel(AppStrings.localized("feed.post_description_optional"))
                            .onChange(of: draftBody) { _, value in
                                if value.count > CommunityContentRules.maximumPostLength {
                                    draftBody = String(value.prefix(CommunityContentRules.maximumPostLength))
                                    return
                                }
                                hashtagSearchDebouncer.schedule { await feedStore.updateHashtagSuggestions(for: value) }
                            }
                    }
                    if !feedStore.hashtagSuggestions.isEmpty {
                        CommunityHashtagSuggestionList(suggestions: feedStore.hashtagSuggestions) { tag in
                            draftBody = CommunityHashtagRules.replacingActiveHashtag(in: draftBody, with: tag)
                            feedStore.clearHashtagSuggestions()
                        }
                    }
                    Text(
                        String(
                            format: AppStrings.localized("feed.character_count"), draftBody.count,
                            CommunityContentRules.maximumPostLength)
                    )
                    .font(.caption)
                    .foregroundStyle(draftBody.count > CommunityContentRules.maximumPostLength ? .red : .secondary)
                }

                Section(AppStrings.localized("media.photos")) {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(1, CommunityContentRules.maximumPostImageCount - preparedImages.count),
                        matching: .images
                    ) {
                        Label(AppStrings.localized("media.add_photos"), systemImage: "photo.on.rectangle.angled")
                    }
                    .accessibilityHint(AppStrings.localized("media.max_six"))
                    .disabled(isLoadingPhotos || preparedImages.count >= CommunityContentRules.maximumPostImageCount)

                    if isLoadingPhotos {
                        ProgressView()
                    }
                    if !preparedImages.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(Array(preparedImages.enumerated()), id: \.offset) { index, image in
                                    NorgeEditableImagePreview(
                                        data: image.data,
                                        editAccessibilityLabel: AppStrings.localized("post_photo.edit"),
                                        removeAccessibilityLabel: AppStrings.localized("media.remove_photo"),
                                        onEdit: {
                                            editingImageIndex = index
                                            imageEditorDraft = CommunityImageDraft(data: image.data, aspect: .free)
                                        },
                                        onRemove: {
                                            preparedImages.remove(at: index)
                                        })
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    Text(
                        String(
                            format: AppStrings.localized("media.photo_count"), preparedImages.count,
                            CommunityContentRules.maximumPostImageCount)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let mediaErrorMessage {
                        NorgeInlineFeedback(message: mediaErrorMessage)
                    }
                }

                Section {
                    Text(AppStrings.localized("feed.compose_notice"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = feedStore.errorMessage {
                    Section {
                        NorgeInlineFeedback(message: errorMessage)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .navigationTitle(AppStrings.localized("feed.new_post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    if feedStore.isPublishing {
                        ProgressView()
                            .accessibilityLabel(AppStrings.localized("media.publishing"))
                    } else {
                        Button(AppStrings.localized("feed.publish")) {
                            Task {
                                let groupID: UUID? =
                                    switch destination {
                                    case .general: nil
                                    case .group(let id): id
                                    }
                                if await feedStore.publish(
                                    title: draftTitle, body: draftBody, kind: kind, groupID: groupID,
                                    media: preparedImages)
                                {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(
                            isLoadingPhotos || imageEditorDraft != nil
                                || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || draftTitle.count > CommunityContentRules.maximumPostTitleLength
                                || draftBody.count > CommunityContentRules.maximumPostLength)
                    }
                }
                .norgePlainToolbar()
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                photoLoadingTask?.cancel()
                photoLoadingTask = Task { @MainActor in
                    isLoadingPhotos = true
                    defer { isLoadingPhotos = false }
                    do {
                        var drafts: [CommunityImageDraft] = []
                        for item in items {
                            guard !Task.isCancelled else { return }
                            if let data = try await item.loadTransferable(type: Data.self) {
                                drafts.append(CommunityImageDraft(data: data, aspect: .free))
                            }
                        }
                        guard !Task.isCancelled else { return }
                        // Picking a photo only creates a local draft. The editor
                        // must confirm it before it is added to this post.
                        queuedImageDrafts = drafts
                        selectedPhotos = []
                        mediaErrorMessage = nil
                        presentNextImageEditor()
                    } catch {
                        mediaErrorMessage = AppStrings.localized("media.processing_error")
                        selectedPhotos = []
                    }
                }
            }
            .sheet(
                item: $imageEditorDraft,
                onDismiss: {
                    editingImageIndex = nil
                    presentNextImageEditor()
                },
                content: { source in
                    CommunityImageEditor(source: source) { data in
                        do {
                            let upload = try await CommunityImageProcessing.prepareJPEG(from: data)
                            if let index = editingImageIndex, preparedImages.indices.contains(index) {
                                preparedImages[index] = upload
                            } else if preparedImages.count < CommunityContentRules.maximumPostImageCount {
                                preparedImages.append(upload)
                            }
                            mediaErrorMessage = nil
                        } catch {
                            mediaErrorMessage = AppStrings.localized("media.processing_error")
                        }
                        imageEditorDraft = nil
                    }
                }
            )
            .onDisappear {
                photoLoadingTask?.cancel()
                hashtagSearchDebouncer.cancel()
                feedStore.clearHashtagSuggestions()
            }
        }
    }

    private func presentNextImageEditor() {
        guard imageEditorDraft == nil, !queuedImageDrafts.isEmpty else { return }
        imageEditorDraft = queuedImageDrafts.removeFirst()
    }

    private func kindTitle(_ kind: CommunityPostKind) -> String {
        AppStrings.localized("feed.kind.\(kind.rawValue)")
    }
}
