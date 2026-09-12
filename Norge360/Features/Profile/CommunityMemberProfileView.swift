import PhotosUI
import SwiftUI

// Profile presentation, editing and media actions share state and ownership
// checks, so this feature remains a single audited vertical slice.
// swiftlint:disable file_length

struct CommunityMemberProfileView: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var followStore: CommunityFollowStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore

    let userID: UUID
    var usesRootTopBar = false
    @State private var profile: CommunityProfile?
    @State private var posts: [CommunityFeedItem] = []
    @State private var stats: CommunityMemberProfileStats?
    @State private var replies: [CommunityFeedItem] = []
    @State private var mediaPosts: [CommunityFeedItem] = []
    @State private var likedPosts: [CommunityFeedItem] = []
    @State private var selectedPostTab: ProfilePostTab = .posts
    @State private var loadedPostTabs: Set<ProfilePostTab> = []
    @State private var isLoadingPostTab = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var imageSourceDestination: ProfileImageDestination?
    @State private var isPresentingCamera = false
    @State private var imageDraft: CommunityImageDraft?
    @State private var imageDestination: ProfileImageDestination = .avatar
    @State private var expandedImage: ExpandedProfileImage?
    @State private var avatarPreview: ExpandedProfileImage?
    @State private var isUploadingAvatar = false
    @State private var isUploadingCover = false
    @State private var isPresentingComposer = false
    @State private var isPresentingProfileEditor = false
    @State private var isPresentingProfileReport = false
    @State private var isPresentingProfileBlock = false
    @State private var hasLoaded = false
    @State private var isRequestingConversation = false

    // A profile reached from a post or conversation is still owned by the
    // authenticated member, regardless of which tab created the destination.
    private var isOwnProfile: Bool { authenticationStore.user?.id == userID }
    private var usesProfileTabChrome: Bool { usesRootTopBar || isOwnProfile }

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState(fillsAvailableSpace: true)
            } else if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        profileHeader(profile)
                        profilePosts
                    }
                    .padding(.bottom, 28)
                }
                .refreshable { await loadProfile() }
            } else if errorMessage != nil {
                ContentUnavailableView {
                    Label(AppStrings.localized("profile.ui.load_error_title"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(AppStrings.localized("profile.ui.load_error_body"))
                } actions: {
                    Button(AppStrings.localized("profile.ui.retry")) {
                        Task { await loadProfile() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView(
                    AppStrings.localized("member.unavailable_title"),
                    systemImage: "lock.fill",
                    description: Text(AppStrings.localized("member.unavailable_body"))
                )
            }
        }
        .background(Color.norgeAppBackground)
        .navigationTitle(profile.map(\.username) ?? AppStrings.localized("member.profile_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(usesProfileTabChrome ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if usesProfileTabChrome {
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

                            if isOwnProfile {
                                profileActions
                            }

                            NavigationLink {
                                ProfileSettingsView()
                            } label: {
                                NorgeTopBarActionLabel(systemName: "gearshape")
                            }
                            .accessibilityLabel(AppStrings.localized("profile.settings"))
                        }

                        NorgeTopBarTitle(
                            text: profile.map(\.username) ?? AppStrings.localized("member.profile_title")
                        )
                        .padding(
                            .horizontal,
                            NorgeTopBarMetrics.actionSize * (isOwnProfile ? 2 : 1)
                                + NorgeTopBarMetrics.itemSpacing
                        )
                    }
                }
            }
        }
        .toolbar {
            if !usesProfileTabChrome {
                ToolbarItem(placement: .topBarTrailing) {
                    profileActions
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            if isOwnProfile, let currentProfile = communityProfileStore.profile {
                profile = currentProfile
                isLoading = false
            }
            await loadProfile()
        }
        .onChange(of: communityProfileStore.profile) { _, updatedProfile in
            guard isOwnProfile, updatedProfile?.userID == userID else { return }
            if let updatedProfile {
                feedStore.applyUpdatedProfile(updatedProfile)
                profile = updatedProfile
            }
        }
        .onChange(of: selectedPostTab) { _, tab in
            Task { await loadPostTab(tab) }
        }
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task { await prepareImage(from: item, destination: .avatar) }
        }
        .onChange(of: coverPickerItem) { _, item in
            guard let item else { return }
            Task { await prepareImage(from: item, destination: .cover) }
        }
        .confirmationDialog(
            AppStrings.localized("media.choose_source"),
            isPresented: Binding(
                get: { imageSourceDestination != nil }, set: { if !$0 { imageSourceDestination = nil } })
        ) {
            if let destination = imageSourceDestination {
                PhotosPicker(
                    selection: destination == .avatar ? $avatarPickerItem : $coverPickerItem, matching: .images
                ) {
                    Text(AppStrings.localized("media.photo_library"))
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(AppStrings.localized("media.camera")) { isPresentingCamera = true }
                }
            }
            Button(AppStrings.localized("common.cancel"), role: .cancel) { imageSourceDestination = nil }
        }
        .sheet(isPresented: $isPresentingCamera) {
            CameraImagePicker { data in
                guard let destination = imageSourceDestination else { return }
                imageSourceDestination = nil
                Task { await prepareImage(data: data, destination: destination) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $imageDraft) { source in
            let destination = imageDestination
            CommunityImageEditor(source: source) { data in
                imageDraft = nil
                await uploadImage(data, destination: destination)
            }
        }
        .fullScreenCover(item: $expandedImage) { image in
            CommunityImageViewer(url: image.url)
                .presentationBackground(.clear)
        }
        .overlay {
            if let avatarPreview {
                CommunityAvatarPreview(url: avatarPreview.url) { self.avatarPreview = nil }
                    .transition(.opacity)
            }
        }
        .navigationDestination(isPresented: $isPresentingProfileEditor) {
            if let profile {
                EditCommunityProfileDetailsView(profile: profile)
            }
        }
        .sheet(
            isPresented: $isPresentingComposer,
            onDismiss: {
                Task { await loadProfile() }
            },
            content: {
                CreateCommunityPostView(
                    joinedGroups: groupsStore.groups.filter { groupsStore.joinedGroupIDs.contains($0.id) }
                )
            }
        )
        .confirmationDialog(
            AppStrings.localized("member.report_title"),
            isPresented: $isPresentingProfileReport,
            titleVisibility: .visible
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    Task {
                        if await feedStore.report(profileID: userID, reason: reason) {
                            noticeMessage = AppStrings.localized("feed.report_sent")
                        } else {
                            errorMessage = AppStrings.localized("feed.report_error")
                        }
                    }
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("member.report_body"))
        }
        .alert(AppStrings.localized("feed.block_title"), isPresented: $isPresentingProfileBlock) {
            Button(AppStrings.localized("feed.block_confirm"), role: .destructive) {
                Task {
                    guard await feedStore.block(authorID: userID) else {
                        errorMessage = AppStrings.localized("feed.block_error")
                        return
                    }
                    profile = nil
                    posts = []
                    stats = nil
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: AppStrings.localized("feed.block_body"),
                    profile?.displayName ?? AppStrings.localized("feed.member")))
        }
        .overlay {
            if let message = errorMessage ?? noticeMessage {
                NorgeInlineFeedback(message: message, kind: errorMessage == nil ? .notice : .error)
            }
        }
    }

}

private enum ProfilePostTab: String, CaseIterable, Hashable, Identifiable {
    case posts
    case replies
    case media
    case liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: AppStrings.localized("member.recent_posts")
        case .replies: AppStrings.localized("member.replies")
        case .media: AppStrings.localized("member.media")
        case .liked: AppStrings.localized("member.liked_posts")
        }
    }

    var emptyTitle: String {
        switch self {
        case .posts: AppStrings.localized("member.no_posts_title")
        case .replies: AppStrings.localized("member.no_replies_title")
        case .media: AppStrings.localized("member.no_media_title")
        case .liked: AppStrings.localized("member.no_liked_posts_title")
        }
    }

    var emptyBody: String {
        switch self {
        case .posts: AppStrings.localized("member.no_posts_body")
        case .replies: AppStrings.localized("member.no_replies_body")
        case .media: AppStrings.localized("member.no_media_body")
        case .liked: AppStrings.localized("member.no_liked_posts_body")
        }
    }
}

extension CommunityMemberProfileView {
    private func profileHeader(_ profile: CommunityProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showImage(profile.coverURL)
            } label: {
                MemberProfileCoverImage(url: profile.coverURL)
            }
            .buttonStyle(.plain)
            .disabled(profile.coverURL == nil)
            .accessibilityLabel(AppStrings.localized("profile.ui.view_cover"))
            .overlay(alignment: .bottomTrailing) { coverEditControl }

            HStack(alignment: .bottom, spacing: 14) {
                Button {
                    showImage(profile.avatarURL, displaysAsAvatar: true)
                } label: {
                    CommunityAvatarView(url: profile.avatarURL, size: 96)
                        .overlay(Circle().stroke(Color.norgeAppBackground, lineWidth: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("profile.ui.view_avatar"))
                .accessibilityHint(AppStrings.localized("profile.ui.avatar_hint"))
                .onLongPressGesture(minimumDuration: 0.3) { showImage(profile.avatarURL, displaysAsAvatar: true) }
                .overlay(alignment: .bottomTrailing) { avatarEditControl }

                profileStats
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.top, -44)
            .padding(.top, 12)

            profileIdentity(profile)
        }
    }

    private func profileIdentity(_ profile: CommunityProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isOwnProfile {
                HStack {
                    relationshipActions
                    Spacer()
                }
            }

            if let biography = profile.biography, !biography.isEmpty {
                Text(biography)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            profileMetadata(profile)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func profileMetadata(_ profile: CommunityProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 10) {
                if profile.showNorwayStatus != false,
                    let norwayStatus = profile.norwayStatus
                {
                    Label(
                        AppStrings.localized("community.status.\(norwayStatus.rawValue)"),
                        systemImage: "sparkle"
                    )
                }
                if profile.showLocation != false,
                    let city = profile.cityOrRegion,
                    !city.isEmpty
                {
                    Label(city, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        }
    }

    @ViewBuilder
    private var coverEditControl: some View {
        if isOwnProfile {
            Button {
                imageSourceDestination = .cover
            } label: {
                ProfileImageEditControl(isUploading: isUploadingCover)
            }
            .padding(12)
            .accessibilityLabel(AppStrings.localized("profile.change_cover"))
            .disabled(isUploadingAvatar || isUploadingCover)
        }
    }

    @ViewBuilder
    private var avatarEditControl: some View {
        if isOwnProfile {
            Button {
                imageSourceDestination = .avatar
            } label: {
                ProfileImageEditControl(isUploading: isUploadingAvatar)
            }
            .offset(x: 7, y: 5)
            .accessibilityLabel(AppStrings.localized("profile.change_avatar"))
            .disabled(isUploadingAvatar || isUploadingCover)
        }
    }

    private var profileStats: some View {
        HStack(alignment: .top, spacing: 16) {
            MemberStat(value: stats?.postsCount ?? 0, title: AppStrings.localized("member.posts"))
            if followState?.canViewFollowers != false {
                NavigationLink {
                    CommunityFollowListView(userID: userID, relationship: .followers)
                } label: {
                    MemberStat(value: followState?.followersCount ?? 0, title: AppStrings.localized("follow.followers"))
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("follow.open_followers"))
            } else {
                MemberStat(value: followState?.followersCount ?? 0, title: AppStrings.localized("follow.followers"))
            }
            if followState?.canViewFollowing != false {
                NavigationLink {
                    CommunityFollowListView(userID: userID, relationship: .following)
                } label: {
                    MemberStat(value: followState?.followingCount ?? 0, title: AppStrings.localized("follow.following"))
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("follow.open_following"))
            } else {
                MemberStat(value: followState?.followingCount ?? 0, title: AppStrings.localized("follow.following"))
            }

        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var profilePosts: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(
                        ProfilePostTab.allCases.filter {
                            $0 != .liked || isOwnProfile || followState?.canViewLikedPosts == true
                        }
                    ) { tab in
                        Button {
                            selectedPostTab = tab
                        } label: {
                            Text(tab.title)
                                .font(.headline)
                                .foregroundStyle(selectedPostTab == tab ? Color.primary : Color.secondary)
                                .padding(.bottom, 8)
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(selectedPostTab == tab ? Color.primary : .clear)
                                        .frame(height: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPostTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }

            postTabContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                        abs(value.translation.width) > 45
                    else { return }
                    selectAdjacentPostTab(direction: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    @ViewBuilder
    private var postTabContent: some View {
        if isLoadingPostTab {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if selectedPostItems.isEmpty {
            ContentUnavailableView(
                selectedPostTab.emptyTitle,
                systemImage: "rectangle.stack",
                description: Text(selectedPostTab.emptyBody)
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(selectedPostItems) { item in
                    CommunityFeedPostView(item: item, showsAuthorFollowAction: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func selectAdjacentPostTab(direction: Int) {
        let visibleTabs = ProfilePostTab.allCases.filter {
            $0 != .liked || isOwnProfile || followState?.canViewLikedPosts == true
        }
        guard let currentIndex = visibleTabs.firstIndex(of: selectedPostTab) else { return }
        let nextIndex = currentIndex + direction
        guard visibleTabs.indices.contains(nextIndex) else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            selectedPostTab = visibleTabs[nextIndex]
        }
    }

    private var selectedPostItems: [CommunityFeedItem] {
        switch selectedPostTab {
        case .posts: posts
        case .replies: replies
        case .media: mediaPosts
        case .liked: likedPosts
        }
    }

    @ViewBuilder
    private var profileActions: some View {
        if isOwnProfile {
            ownerActions
        } else {
            memberActions
        }
    }

    private var ownerActions: some View {
        Menu {
            Button {
                isPresentingProfileEditor = true
            } label: {
                Label(AppStrings.localized("profile.edit_details"), systemImage: "person.crop.rectangle")
            }
            ShareLink(item: profileShareURL) {
                Label(AppStrings.localized("member.share_profile"), systemImage: "square.and.arrow.up")
            }
        } label: {
            NorgeTopBarActionLabel(systemName: "ellipsis")
        }
        .accessibilityLabel(AppStrings.localized("member.profile_actions"))
    }

    private var memberActions: some View {
        Menu {
            ShareLink(item: profileShareURL) {
                Label(AppStrings.localized("member.share_profile"), systemImage: "square.and.arrow.up")
            }
            Button(AppStrings.localized("member.report"), systemImage: "exclamationmark.bubble") {
                isPresentingProfileReport = true
            }
            Button(AppStrings.localized("feed.block"), systemImage: "hand.raised.slash", role: .destructive) {
                isPresentingProfileBlock = true
            }
        } label: {
            NorgeTopBarActionLabel(systemName: "ellipsis")
        }
        .accessibilityLabel(AppStrings.localized("member.profile_actions"))
    }

    private var relationshipActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleFollow() }
            } label: {
                Group {
                    if followStore.updatingUserIDs.contains(userID) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(
                            AppStrings.localized(
                                followState?.isFollowing == true ? "follow.unfollow" : "follow.follow"),
                            systemImage: followState?.isFollowing == true
                                ? "person.badge.checkmark" : "person.badge.plus"
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 96, minHeight: 34)
            }
            .foregroundStyle(.white)
            .background(
                Capsule().fill(
                    followState?.isFollowing == true ? Color.red : Color.norgePrimary
                )
            )
            .disabled(followStore.updatingUserIDs.contains(userID))
            .accessibilityLabel(
                AppStrings.localized(followState?.isFollowing == true ? "follow.unfollow" : "follow.follow"))

            Button {
                Task { await requestConversation() }
            } label: {
                Group {
                    if isRequestingConversation {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "message")
                    }
                }
                .font(.title3)
                .frame(width: 44, height: 34)
            }
            .foregroundStyle(Color.primary)
            .disabled(isRequestingConversation)
            .accessibilityLabel(AppStrings.localized("messages.start"))
        }
        .buttonStyle(.plain)
    }

    private func loadProfile() async {
        isLoading = profile == nil
        errorMessage = nil
        defer { isLoading = false }
        do {
            if isOwnProfile {
                await communityProfileStore.refreshProfile()
                profile = communityProfileStore.profile
            } else {
                profile = try await feedStore.memberProfile(for: userID)
            }
            guard profile != nil else { return }
            async let postsRequest = feedStore.memberPosts(for: userID)
            async let statsRequest = feedStore.memberStats(for: userID)
            (posts, stats) = try await (postsRequest, statsRequest)
            loadedPostTabs.insert(.posts)
            try await followStore.loadState(for: userID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppStrings.localized("profile.ui.load_error_body")
        }
    }

    private func loadPostTab(_ tab: ProfilePostTab) async {
        guard tab != .posts, !loadedPostTabs.contains(tab), profile != nil else { return }
        isLoadingPostTab = true
        defer { isLoadingPostTab = false }
        do {
            switch tab {
            case .posts:
                break
            case .replies:
                replies = try await feedStore.memberReplies(for: userID)
            case .media:
                mediaPosts = try await feedStore.memberMedia(for: userID)
            case .liked:
                likedPosts = try await feedStore.likedPosts(for: userID)
            }
            loadedPostTabs.insert(tab)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppStrings.localized("profile.ui.load_error_body")
        }
    }

    private var followState: CommunityFollowState? { followStore.states[userID] }

    private var profileShareURL: URL {
        URL(string: "https://norge360.com/\(profile?.username ?? "profile")") ?? URL(fileURLWithPath: "/")
    }

    private func toggleFollow() async {
        errorMessage = nil
        do { try await followStore.toggleFollow(for: userID) } catch {
            errorMessage = AppStrings.localized("follow.error")
        }
    }

    private func requestConversation() async {
        errorMessage = nil
        isRequestingConversation = true
        defer { isRequestingConversation = false }
        do {
            _ = try await conversationsStore.requestConversation(with: userID)
            noticeMessage = AppStrings.localized("messages.request_sent")
        } catch {
            errorMessage = messageRequestError(for: error)
        }
    }

    private func messageRequestError(for error: Error) -> String {
        let description = String(reflecting: error).lowercased()
        if description.contains("invalid conversation target") {
            return AppStrings.localized("messages.request_invalid_target")
        }
        if description.contains("message request unavailable") || description.contains("conversation unavailable") {
            return AppStrings.localized("messages.request_unavailable")
        }
        return AppStrings.localized("messages.error")
    }

    private func prepareImage(from item: PhotosPickerItem, destination: ProfileImageDestination) async {
        errorMessage = nil
        setImageLoading(true, destination: destination)
        defer {
            setImageLoading(false, destination: destination)
            avatarPickerItem = nil
            coverPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CommunityMediaError.unsupportedImage
            }
            imageDestination = destination
            imageDraft = CommunityImageDraft(data: data, aspect: destination == .avatar ? .avatar : .cover)
        } catch {
            errorMessage = AppStrings.localized(destination == .avatar ? "profile.avatar_error" : "profile.cover_error")
        }
    }

    private func prepareImage(data: Data, destination: ProfileImageDestination) async {
        errorMessage = nil
        setImageLoading(true, destination: destination)
        defer { setImageLoading(false, destination: destination) }
        imageDestination = destination
        imageDraft = CommunityImageDraft(data: data, aspect: destination == .avatar ? .avatar : .cover)
    }

    private func uploadImage(_ data: Data, destination: ProfileImageDestination) async {
        setImageLoading(true, destination: destination)
        errorMessage = nil
        defer { setImageLoading(false, destination: destination) }
        do {
            let prepared = try await CommunityImageProcessing.prepareJPEG(from: data)
            switch destination {
            case .avatar: try await communityProfileStore.updateAvatar(with: prepared)
            case .cover: try await communityProfileStore.updateCover(with: prepared)
            }
            feedStore.invalidateMemberContent()
            profile = communityProfileStore.profile
        } catch {
            errorMessage = AppStrings.localized(destination == .avatar ? "profile.avatar_error" : "profile.cover_error")
        }
    }

    private func setImageLoading(_ loading: Bool, destination: ProfileImageDestination) {
        switch destination {
        case .avatar: isUploadingAvatar = loading
        case .cover: isUploadingCover = loading
        }
    }

    private func showImage(_ url: URL?, displaysAsAvatar: Bool = false) {
        guard let url else { return }
        if displaysAsAvatar {
            withAnimation(.easeOut(duration: 0.18)) {
                avatarPreview = ExpandedProfileImage(url: url)
            }
        } else {
            expandedImage = ExpandedProfileImage(url: url)
        }
    }

}

private struct ProfileImageEditControl: View {
    let isUploading: Bool

    nonisolated init(isUploading: Bool) {
        self.isUploading = isUploading
    }

    var body: some View {
        Group {
            if isUploading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "camera.fill").font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(Color.primary)
        .frame(width: 34, height: 34)
        .background(Color.norgeAppBackground, in: Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

}

private enum ProfileImageDestination: Equatable { case avatar, cover }

private struct ExpandedProfileImage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Instagram-style avatar presentation: the profile remains visible behind a
/// restrained dim layer and the round image is a centred, large preview—not a
/// separate black full-screen image viewer.
private struct CommunityAvatarPreview: View {
    let url: URL
    let dismiss: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.norgeAppBackground.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            ZStack {
                CommunityCachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 264, height: 264)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
            .scaleEffect(zoomScale)
            .offset(y: dragOffset)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        // Dampen pinch input so the preview grows slowly and
                        // never keeps the temporary zoom after the gesture.
                        zoomScale = min(max(1 + (value - 1) * 0.38, 1), 2.4)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.3)) { zoomScale = 1 }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded {
                        if zoomScale == 1, $0.translation.height > 70 {
                            dismiss()
                        } else {
                            withAnimation(.spring(duration: 0.22)) { dragOffset = 0 }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.25)) {
                    zoomScale = zoomScale == 1 ? 2 : 1
                }
            }
        }
        .accessibilityAction(.escape, dismiss)
    }
}

private struct MemberProfileCoverImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url {
                    CommunityCachedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.norgePrimary.opacity(0.75), Color.teal.opacity(0.28), Color.norgeInputSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct MemberStat: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value, format: .number)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Wrap public metadata at the available width, including at accessibility sizes.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var horizontalPosition: CGFloat = 0
        var verticalPosition: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let gap = horizontalPosition == 0 ? 0 : spacing
            if horizontalPosition > 0, horizontalPosition + gap + size.width > maxWidth {
                usedWidth = max(usedWidth, horizontalPosition)
                horizontalPosition = 0
                verticalPosition += rowHeight + spacing
                rowHeight = 0
            }
            horizontalPosition += (horizontalPosition == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? max(usedWidth, horizontalPosition), height: verticalPosition + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let gap = point.x == bounds.minX ? 0 : spacing
            if point.x > bounds.minX, point.x + gap + size.width > bounds.maxX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            if point.x > bounds.minX { point.x += spacing }
            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
