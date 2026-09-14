import PhotosUI
import SwiftUI

// The feed screen keeps composer, media-editor and feed lifecycle code together
// so their cancellation and upload state transitions remain local.
// swiftlint:disable file_length

enum UpcomingEventsHomePreference {
    static let hiddenKey = "home.upcoming_events.hidden"
}

struct CommunityFeedView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var followStore: CommunityFollowStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore

    @State private var isPresentingComposer = false
    @State private var isNotificationsPresented = false
    @State private var isHeaderVisible = true
    @State private var feedFilter: FeedFilter = .forYou
    @State private var followedMemberIDs: Set<UUID> = []
    @State private var forYouRefreshToken = Int.random(in: 1...Int.max)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("home-top")

                        ScrollHeaderVisibilityObserver { visible in
                            if isHeaderVisible != visible {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isHeaderVisible = visible
                                }
                            }
                            tabRouter.setTabBarCompact(!visible, for: .home)
                        }
                        .frame(height: 0)

                        LazyVStack(alignment: .leading, spacing: NorgeLayoutMetrics.feedItemSpacing) {
                            composerPrompt

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
                                    items: eventsStore.prioritizedItems(
                                        for: communityProfileStore.profile?.cityOrRegion))
                                ForEach(displayedItems) { item in
                                    CommunityFeedPostView(item: item)
                                        .onAppear {
                                            loadMoreIfNeeded(afterDisplaying: item, in: displayedItems)
                                        }
                                }

                                if feedStore.isLoadingMore {
                                    NorgeSkeletonList(rowCount: 1)
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
                        .padding(.bottom, NorgeSpacing.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.norgeAppBackground)
                .contentMargins(.top, 0, for: .scrollContent)
                .onChange(of: tabRouter.homeScrollToTopToken) { _, _ in
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo("home-top", anchor: .top)
                    }
                }
            }
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

                                Button {
                                    isNotificationsPresented = true
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
                                .font(.headline)
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
            .navigationDestination(isPresented: $isNotificationsPresented) {
                CommunityNotificationsView()
            }
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
            .overlay {
                if isPresentingComposer {
                    CreateCommunityPostView(
                        joinedGroups: groupsStore.groups.filter { groupsStore.joinedGroupIDs.contains($0.id) },
                        onDismiss: { isPresentingComposer = false }
                    )
                    .background(Color.norgeAppBackground.ignoresSafeArea())
                    .ignoresSafeArea()
                    .zIndex(10)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
            .onChange(of: isNotificationsPresented) { _, isPresented in
                tabRouter.isHomeNotificationsFlowActive = isPresented
                tabRouter.isTabBarHidden = isPresented
            }
            .onChange(of: isPresentingComposer) { _, isPresented in
                tabRouter.isTabBarHidden = isPresented || isNotificationsPresented
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

extension CommunityFeedView {
    private var composerPrompt: some View {
        Button {
            isPresentingComposer = true
        } label: {
            HStack(alignment: .center, spacing: 8) {
                CommunityAvatarView(url: communityProfileStore.profile?.avatarURL, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(communityProfileStore.profile?.displayName ?? AppStrings.localized("feed.member"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(AppStrings.localized("feed.compose_prompt"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(ComposerPromptButtonStyle())
        .hoverEffectDisabled(true)
        .accessibilityLabel(AppStrings.localized("feed.compose"))
        .accessibilityHint(AppStrings.localized("feed.compose_hint"))
    }

    private struct ComposerPromptButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
}

struct CommunityEventFeedRail: View {
    let items: [CommunityEventItem]
    @AppStorage(UpcomingEventsHomePreference.hiddenKey) private var isHidden = false
    @State private var isShowingAllEvents = false

    var body: some View {
        if !items.isEmpty && !isHidden {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Label(AppStrings.localized("feed.upcoming_events"), systemImage: "calendar")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Menu {
                        Button(AppStrings.localized("events.view_all"), systemImage: "calendar") {
                            isShowingAllEvents = true
                        }
                        Button(AppStrings.localized("feed.hide_upcoming_events"), systemImage: "eye.slash") {
                            isHidden = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.localized("feed.upcoming_events_actions"))
                }
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
            .navigationDestination(isPresented: $isShowingAllEvents) {
                CommunityEventsView()
            }
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
    @State private var isSaving = false
    @State private var feedbackMessage: String?
    @State private var hasError = false

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
            await loadAuthorFollowState()
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
            isSaved: feedStore.savedPostIDs.contains(currentItem.id),
            isSaving: isSaving || feedStore.savingPostIDs.contains(currentItem.id),
            showsAuthorFollowAction: showsAuthorFollowAction,
            isAuthorFollowed: followStore.states[currentItem.post.authorID]?.isFollowing == true,
            isAuthorFollowStateLoaded: followStore.loadedUserIDs.contains(currentItem.post.authorID),
            isFollowingAuthor: followStore.updatingUserIDs.contains(currentItem.post.authorID),
            onToggleLike: { Task { await toggleLike() } },
            onFollowAuthor: { Task { await followAuthor() } },
            onOpenComments: { isShowingComments = true },
            onToggleSave: { Task { await toggleSave() } },
            onEdit: { isEditing = true },
            onDelete: { isDeleting = true },
            onShowEditHistory: { isShowingHistory = true },
            onReport: { isReporting = true },
            onBlock: { isBlocking = true }
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

    private func toggleSave() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await feedStore.toggleSave(postID: currentItem.id)
        if let error = feedStore.errorMessage {
            feedbackMessage = error
            hasError = true
        } else {
            feedbackMessage = nil
            hasError = false
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
            feedbackMessage = UserFacingErrorMapper.message(
                for: error,
                fallbackKey: "feed.error",
                operation: "post.refresh"
            )
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
    @Environment(\.colorScheme) private var colorScheme
    let item: CommunityFeedItem
    let group: CommunityGroup?
    let isDetail: Bool
    let isCurrentUser: Bool
    let isLiking: Bool
    let isSaved: Bool
    let isSaving: Bool
    let showsAuthorFollowAction: Bool
    let isAuthorFollowed: Bool
    let isAuthorFollowStateLoaded: Bool
    let isFollowingAuthor: Bool
    let onToggleLike: () -> Void
    let onFollowAuthor: () -> Void
    let onOpenComments: () -> Void
    let onToggleSave: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShowEditHistory: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    @State private var isShowingWhyThisPost = false
    @State private var isPostExpanded = false
    @State private var previewProfile: CommunityProfile?
    @State private var suppressProfileOpen = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
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
                                AppStrings.localized("feed.report"), systemImage: "exclamationmark.bubble",
                                action: onReport
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

                if item.editHistoryCount > 0 {
                    Button(AppStrings.localized("post.edited"), action: onShowEditHistory)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 32)
                        .accessibilityHint(AppStrings.localized("post.edit_history_hint"))
                }

                HStack(spacing: 2) {
                    Button(action: onToggleLike) {
                        postActionLabel(
                            item.likesCount > 0 ? "\(item.likesCount)" : nil,
                            symbol: item.isLikedByCurrentUser ? "heart.fill" : "heart"
                        )
                        .foregroundStyle(item.isLikedByCurrentUser ? Color.red : actionForeground)
                        .frame(minWidth: 46, minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLiking)
                    .accessibilityLabel(
                        item.isLikedByCurrentUser
                            ? AppStrings.localized("likes.remove") : AppStrings.localized("likes.add")
                    )
                    .accessibilityValue(String(format: AppStrings.localized("likes.count"), item.likesCount))

                    Button(action: onOpenComments) {
                        postActionLabel(
                            item.commentsCount > 0 ? "\(item.commentsCount)" : nil,
                            symbol: "bubble.right"
                        )
                        .frame(minWidth: 46, minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(actionForeground)
                    .accessibilityLabel(AppStrings.localized("comments.open"))
                    .accessibilityValue(String(format: AppStrings.localized("comments.count"), item.commentsCount))

                    ShareLink(item: postShareURL) {
                        postActionLabel(nil, symbol: "paperplane")
                            .frame(minWidth: 46, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(actionForeground)
                    .accessibilityLabel(AppStrings.localized("feed.share_post"))

                    Spacer(minLength: 0)

                    Button(action: onToggleSave) {
                        postActionLabel(nil, symbol: isSaved ? "bookmark.fill" : "bookmark")
                            .frame(minWidth: 46, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSaved ? Color.norgePrimary : actionForeground)
                    .disabled(isSaving)
                    .accessibilityLabel(
                        AppStrings.localized(isSaved ? "feed.unsave_post" : "feed.save_post")
                    )
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .padding(.top, -4)

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

            if let profile = previewProfile {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissProfilePreview() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(10)

                profilePreviewCard(profile)
                    .offset(y: 52)
                    .zIndex(11)
            }
        }
        .alert(AppStrings.localized("feed.why_this_post"), isPresented: $isShowingWhyThisPost) {
            Button(AppStrings.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(whyThisPostMessage)
        }
        .animation(.easeOut(duration: 0.16), value: previewProfile?.userID)
        .onReceive(NotificationCenter.default.publisher(for: .norgeNonInputInteraction)) { _ in
            dismissProfilePreview()
        }
    }

    private func openAuthorProfile() {
        guard !suppressProfileOpen else { return }
        tabRouter.openProfile(item.post.authorID)
    }

    private func open(_ userID: UUID) {
        tabRouter.openProfile(userID)
    }

    private func dismissProfilePreview() {
        previewProfile = nil
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

    @ViewBuilder
    private func profilePreviewCard(_ profile: CommunityProfile) -> some View {
        Group {
            if isCurrentUser {
                Button {
                    dismissProfilePreview()
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
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissProfilePreview()
                    }
                )
            }
        }
        .buttonStyle(.plain)
        .frame(width: 232, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            Color.norgeAppBackground,
            in: RoundedRectangle(cornerRadius: NorgeCornerRadius.card, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: dismissProfilePreview) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.norgeInputSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(AppStrings.localized("common.cancel"))
        }
        .overlay {
            RoundedRectangle(cornerRadius: NorgeCornerRadius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
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
            CommunityPostMediaCarousel(media: item.media, postContext: fullscreenPostContext)
        }
    }

    private var fullscreenPostContext: CommunityFullscreenPostContext {
        CommunityFullscreenPostContext(
            item: item,
            isCurrentUser: isCurrentUser,
            showsAuthorFollowAction: true,
            isLiking: isLiking,
            isSaved: isSaved,
            isSaving: isSaving,
            isAuthorFollowed: isAuthorFollowed,
            isAuthorFollowStateLoaded: isAuthorFollowStateLoaded,
            isFollowingAuthor: isFollowingAuthor,
            postURL: postShareURL,
            onToggleLike: onToggleLike,
            onOpenComments: onOpenComments,
            onToggleSave: onToggleSave,
            onFollowAuthor: onFollowAuthor,
            onReport: onReport
        )
    }

    private var postShareURL: URL {
        URL(string: "https://norge360.com/posts/\(item.id.uuidString)")
            ?? URL(fileURLWithPath: "/")
    }

    private func timestamp(for date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }

    private func postActionLabel(_ title: String?, symbol: String) -> some View {
        HStack(spacing: title == nil ? 0 : 3) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var actionForeground: Color {
        colorScheme == .dark ? .white : .secondary
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
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore

    let joinedGroups: [CommunityGroup]
    private let onDismiss: (() -> Void)?
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

    init(
        joinedGroups: [CommunityGroup],
        initialDestination: Destination = .general,
        onDismiss: (() -> Void)? = nil
    ) {
        self.joinedGroups = joinedGroups
        self.onDismiss = onDismiss
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composerHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: NorgeSpacing.small) {
                            CommunityAvatarView(url: communityProfileStore.profile?.avatarURL, size: 42)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 0) {
                                TextField(AppStrings.localized("feed.post_title"), text: $draftTitle)
                                    .font(.title3.weight(.semibold))
                                    .textFieldStyle(.plain)
                                    .lineLimit(1)
                                    .onChange(of: draftTitle) { _, value in
                                        if value.count > CommunityContentRules.maximumPostTitleLength {
                                            draftTitle = String(
                                                value.prefix(CommunityContentRules.maximumPostTitleLength)
                                            )
                                        }
                                    }

                                TextField(
                                    AppStrings.localized("feed.post_description_optional"),
                                    text: $draftBody,
                                    axis: .vertical
                                )
                                .font(.body)
                                .lineLimit(1...10)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 5)
                                .accessibilityLabel(AppStrings.localized("feed.post_description_optional"))
                                .onChange(of: draftBody) { _, value in
                                    if value.count > CommunityContentRules.maximumPostLength {
                                        draftBody = String(value.prefix(CommunityContentRules.maximumPostLength))
                                        return
                                    }
                                    hashtagSearchDebouncer.schedule {
                                        await feedStore.updateHashtagSuggestions(for: value)
                                    }
                                }

                                if !feedStore.hashtagSuggestions.isEmpty {
                                    CommunityHashtagSuggestionList(suggestions: feedStore.hashtagSuggestions) { tag in
                                        draftBody = CommunityHashtagRules.replacingActiveHashtag(
                                            in: draftBody, with: tag
                                        )
                                        feedStore.clearHashtagSuggestions()
                                    }
                                }
                            }
                        }

                        if !preparedImages.isEmpty {
                            preparedImagesPreview
                                .padding(.horizontal, -NorgeSpacing.medium)
                                .padding(.horizontal, NorgeSpacing.small)
                                .padding(.top, NorgeSpacing.small)
                        }

                        if let mediaErrorMessage {
                            NorgeInlineFeedback(message: mediaErrorMessage)
                                .padding(.top, NorgeSpacing.small)
                        }

                        if let errorMessage = feedStore.errorMessage {
                            NorgeInlineFeedback(message: errorMessage)
                                .padding(.top, NorgeSpacing.small)
                        }
                    }
                    .padding(.horizontal, NorgeSpacing.medium)
                    .padding(.top, NorgeSpacing.small)
                    .padding(.bottom, NorgeSpacing.large)
                }
                .scrollDismissesKeyboard(.interactively)
                composerAttachmentBar
            }
            .background(Color.norgeAppBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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

    private var composerHeader: some View {
        HStack(spacing: NorgeSpacing.small) {
            Button(AppStrings.localized("feed.cancel")) { closeComposer() }
                .font(.body)
                .foregroundStyle(.primary)
                .frame(minWidth: 60, alignment: .leading)

            Spacer(minLength: 0)

            Text(AppStrings.localized("feed.new_post"))
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if feedStore.isPublishing {
                ProgressView()
                    .frame(width: 72, height: 38)
                    .accessibilityLabel(AppStrings.localized("media.publishing"))
            } else {
                Button(AppStrings.localized("feed.publish")) {
                    Task { await publishPost() }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canPublish ? .white : .secondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(canPublish ? Color.norgePrimary : Color.norgeInputSurface, in: Capsule())
                .disabled(!canPublish)
            }
        }
        .padding(.horizontal, NorgeSpacing.medium)
        .frame(minHeight: NorgeTopBarMetrics.height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var preparedImagesPreview: some View {
        GeometryReader { proxy in
            let previewHeight: CGFloat = preparedImages.count == 1 ? 300 : 220
            let maximumWidth = preparedImages.count == 1 ? proxy.size.width : proxy.size.width * 0.78

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NorgeSpacing.small) {
                    ForEach(Array(preparedImages.enumerated()), id: \.offset) { index, image in
                        preparedImagePreview(
                            image,
                            index: index,
                            width: preparedImages.count == 1
                                ? proxy.size.width
                                : previewWidth(
                                    for: image,
                                    height: previewHeight,
                                    maximumWidth: maximumWidth
                                ),
                            height: previewHeight
                        )
                    }
                }
            }
        }
        .frame(height: preparedImages.count == 1 ? 300 : 220)
    }

    private func preparedImagePreview(
        _ image: CommunityImageUpload,
        index: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
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
            },
            size: 112,
            width: width,
            height: height
        )
    }

    private func previewWidth(
        for image: CommunityImageUpload,
        height: CGFloat,
        maximumWidth: CGFloat
    ) -> CGFloat {
        let aspectRatio = CGFloat(image.width) / CGFloat(max(1, image.height))
        return min(maximumWidth, max(144, height * aspectRatio))
    }

    private func composerOptionLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: NorgeSpacing.xxs) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.norgePrimary)
        .frame(minHeight: NorgeControlSize.tapTarget)
        .contentShape(Rectangle())
    }

    private var composerAttachmentBar: some View {
        HStack(spacing: NorgeSpacing.small) {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: max(1, CommunityContentRules.maximumPostImageCount - preparedImages.count),
                matching: .images
            ) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.norgePrimary)
                    .frame(width: NorgeControlSize.tapTarget, height: NorgeControlSize.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppStrings.localized("media.add_photos"))
            .accessibilityHint(AppStrings.localized("media.max_six"))
            .disabled(isLoadingPhotos || preparedImages.count >= CommunityContentRules.maximumPostImageCount)

            Menu {
                Button {
                    destination = .general
                } label: {
                    Label(
                        AppStrings.localized("feed.general"),
                        systemImage: destination == .general ? "checkmark" : "globe"
                    )
                }

                ForEach(joinedGroups) { group in
                    Button {
                        destination = .group(group.id)
                    } label: {
                        Label(
                            group.name,
                            systemImage: destination == .group(group.id) ? "checkmark" : "person.3"
                        )
                    }
                }
            } label: {
                composerOptionLabel(
                    systemImage: destination == .general ? "globe" : "person.3",
                    title: destinationTitle
                )
            }
            .accessibilityLabel(AppStrings.localized("feed.share_to"))
            .accessibilityValue(destinationTitle)

            Menu {
                ForEach(CommunityPostKind.allCases) { candidate in
                    Button {
                        kind = candidate
                    } label: {
                        Label(
                            kindTitle(candidate),
                            systemImage: kind == candidate ? "checkmark" : "text.bubble"
                        )
                    }
                }
            } label: {
                composerOptionLabel(
                    systemImage: "square.and.pencil",
                    title: kindTitle(kind)
                )
            }
            .accessibilityLabel(AppStrings.localized("feed.post_type"))
            .accessibilityValue(kindTitle(kind))

            if isLoadingPhotos {
                ProgressView()
                    .padding(.leading, NorgeSpacing.xxs)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NorgeSpacing.medium)
        .padding(.top, NorgeSpacing.xxs)
        .padding(.bottom, NorgeSpacing.small)
        .background(Color.norgeTopBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var destinationTitle: String {
        switch destination {
        case .general:
            return AppStrings.localized("feed.general")
        case .group(let id):
            return joinedGroups.first(where: { $0.id == id })?.name ?? AppStrings.localized("feed.general")
        }
    }

    private var canPublish: Bool {
        !isLoadingPhotos
            && imageEditorDraft == nil
            && !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftTitle.count <= CommunityContentRules.maximumPostTitleLength
            && draftBody.count <= CommunityContentRules.maximumPostLength
    }

    private func publishPost() async {
        let groupID: UUID? =
            switch destination {
            case .general: nil
            case .group(let id): id
            }

        if await feedStore.publish(
            title: draftTitle,
            body: draftBody,
            kind: kind,
            groupID: groupID,
            media: preparedImages
        ) {
            closeComposer()
        }
    }

    private func closeComposer() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
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
