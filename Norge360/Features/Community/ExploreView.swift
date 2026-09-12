import SwiftUI

// Explore keeps search guidance and the explainable ranking in one surface.

struct ExploreView: View {  // swiftlint:disable:this type_body_length
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var showsLatest = false
    @State private var forYouRefreshToken = Int.random(in: 1...Int.max)
    @State private var seenForYouPostIDs: Set<UUID> = []
    @State private var searchPostItems: [CommunityFeedItem] = []
    @State private var isLoadingSearchPosts = false
    @State private var searchRequestGeneration = 0
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var searchHistoryStore: CommunitySearchHistoryStore
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NorgeTopBar {
                    NorgeTopBarSearchField(
                        text: $query,
                        prompt: AppStrings.localized("explore.search_prompt"),
                        focus: $isSearchFocused,
                        showsClearButton: false
                    ) {
                        Group {
                            if isSearchFocused {
                                Button(action: cancelSearch) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: NorgeTopBarMetrics.searchHeight)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppStrings.localized("search.clear"))
                            } else {
                                Menu {
                                    Button(
                                        AppStrings.localized("explore.relevant"),
                                        systemImage: showsLatest ? "circle" : "checkmark"
                                    ) { showsLatest = false }
                                    Button(
                                        AppStrings.localized("explore.latest"),
                                        systemImage: showsLatest ? "checkmark" : "circle"
                                    ) { showsLatest = true }
                                } label: {
                                    NorgeTopBarActionLabel(systemName: "line.3.horizontal.decrease")
                                }
                                .accessibilityLabel(AppStrings.localized("explore.sort"))
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: isSearchFocused)
                    }
                }

                Group {
                    if isSearchFocused && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        recentSearches
                    } else if let tag = CommunityHashtagRules.searchTag(from: query) {
                        if feedStore.isLoadingHashtag {
                            ProgressView()
                        } else {
                            postResults(
                                feedStore.hashtagItems,
                                emptyTitle: String(
                                    format: AppStrings.localized("explore.hashtag_empty_title"), "#\(tag)"))
                        }
                    } else if CommunitySearchRules.normalizedQuery(query) != nil {
                        searchResults
                    } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        guidance("explore.search_minimum_body")
                    } else if feedStore.isLoading && feedStore.items.isEmpty {
                        ProgressView()
                    } else {
                        postResults(displayedPosts)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .norgeScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await feedStore.activate()
                await groupsStore.activate()
                await eventsStore.activate()
            }
            .task(id: query) {
                searchRequestGeneration &+= 1
                let requestGeneration = searchRequestGeneration
                if let tag = CommunityHashtagRules.searchTag(from: query) {
                    searchStore.clear()
                    searchPostItems = []
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await feedStore.loadHashtagPosts(tag: tag)
                    return
                }
                feedStore.clearHashtagPosts()
                guard let normalizedQuery = CommunitySearchRules.normalizedQuery(query) else {
                    searchStore.clear()
                    searchPostItems = []
                    return
                }
                searchPostItems = []
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await searchStore.search(query: normalizedQuery)
                guard !Task.isCancelled, requestGeneration == searchRequestGeneration else { return }

                isLoadingSearchPosts = true
                defer {
                    if requestGeneration == searchRequestGeneration {
                        isLoadingSearchPosts = false
                    }
                }
                let postIDs = searchStore.results.posts.map(\.id)
                guard !postIDs.isEmpty else {
                    searchPostItems = []
                    return
                }
                let loadedPosts = try? await feedStore.posts(for: postIDs)
                guard !Task.isCancelled, requestGeneration == searchRequestGeneration else { return }
                searchPostItems = loadedPosts ?? []
            }
            .onChange(of: tabRouter.exploreScrollToTopToken) { _, _ in
                cancelSearch()
            }
        }
    }

    private var displayedPosts: [CommunityFeedItem] {
        showsLatest
            ? CommunityDiscoveryRules.latestPosts(from: feedStore.items)
            : CommunityDiscoveryRules.forYouPosts(
                from: feedStore.items,
                joinedGroupIDs: groupsStore.joinedGroupIDs,
                surface: .explore,
                refreshToken: forYouRefreshToken,
                seenPostIDs: seenForYouPostIDs
            )
    }

    private func guidance(_ key: String) -> some View {
        NorgeUnavailableState(
            AppStrings.localized("explore.search_title"), systemImage: "magnifyingglass",
            description: AppStrings.localized(key)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(searchDismissDrag)
    }

    private func postResults(_ posts: [CommunityFeedItem], emptyTitle: String? = nil) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("explore-top")
                LazyVStack(alignment: .leading, spacing: NorgeLayoutMetrics.feedItemSpacing) {
                    if let error = feedStore.errorMessage {
                        NorgeInlineFeedback(message: error)
                    }
                    if posts.isEmpty {
                        NorgeUnavailableState(
                            emptyTitle ?? AppStrings.localized("explore.empty_title"), systemImage: "rectangle.stack",
                            description: AppStrings.localized("explore.empty_body"))
                    }
                    CommunityEventFeedRail(
                        items: eventsStore.prioritizedItems(for: communityProfileStore.profile?.cityOrRegion))
                    ForEach(posts) { item in
                        CommunityFeedPostView(item: item)
                            .onAppear {
                                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !showsLatest {
                                    seenForYouPostIDs.insert(item.id)
                                }
                                loadMoreIfNeeded(afterDisplaying: item, in: posts)
                            }
                    }
                    if feedStore.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, NorgeSpacing.medium).padding(.vertical, NorgeSpacing.medium)
            }
            .onChange(of: tabRouter.exploreScrollToTopToken) { _, _ in
                withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("explore-top", anchor: .top) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(searchDismissDrag)
        .refreshable {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !showsLatest {
                forYouRefreshToken &+= 1
                await feedStore.reload()
                // A second page gives the session's viewed-post preference a
                // fresh pool instead of merely reordering the same first page.
                if feedStore.canLoadMore { await feedStore.loadMore() }
            } else {
                await feedStore.refreshIfNeeded()
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searchStore.isSearching || isLoadingSearchPosts {
            NorgeLoadingState()
        } else if let error = searchStore.errorMessage {
            VStack(spacing: 0) {
                NorgeInlineFeedback(message: error)
                guidance("explore.empty_body")
            }
        } else if searchStore.results.profiles.isEmpty && searchStore.results.groups.isEmpty
            && searchPostItems.isEmpty
        {
            guidance("explore.empty_body")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !searchStore.results.profiles.isEmpty {
                        sectionTitle("explore.people")
                        ForEach(searchStore.results.profiles) { profile in
                            Button {
                                searchHistoryStore.record(profile: profile)
                                tabRouter.openProfile(profile.userID)
                            } label: {
                                HStack {
                                    CommunityMemberIdentityView(
                                        displayName: profile.displayName,
                                        username: profile.username,
                                        avatarURL: profile.avatarURL,
                                        avatarSize: 46
                                    )
                                    Spacer()
                                }
                                .frame(minHeight: 54)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if !searchStore.results.groups.isEmpty {
                        sectionTitle("explore.groups")
                        ForEach(searchStore.results.groups) { group in
                            NavigationLink {
                                CommunityGroupDetailView(group: group)
                            } label: {
                                HStack(spacing: 12) {
                                    CommunityAvatarView(url: group.photoURL, size: 46)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(group.name).font(.body.weight(.semibold))
                                        Text(group.description).font(.subheadline).foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }.frame(minHeight: 54)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !searchPostItems.isEmpty {
                        sectionTitle("explore.posts")
                        ForEach(searchPostItems) { item in
                            CommunityFeedPostView(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(searchDismissDrag)
        }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(AppStrings.localized(key)).font(.title3.weight(.bold)).padding(.top, 10)
    }

    private var recentSearches: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppStrings.localized("explore.recent_searches")).font(.title3.weight(.bold))
                    Spacer()
                    if !searchHistoryStore.entries.isEmpty {
                        Button(AppStrings.localized("explore.clear_all_recent_searches")) {
                            searchHistoryStore.clear()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.norgePrimary)
                    }
                }
                .padding(.bottom, 6)
                if searchHistoryStore.entries.isEmpty {
                    guidance("explore.search_empty_body")
                        .frame(minHeight: 240)
                } else {
                    ForEach(searchHistoryStore.entries) { entry in
                        HStack(spacing: 12) {
                            Button {
                                tabRouter.openProfile(entry.profile.userID)
                            } label: {
                                CommunityMemberIdentityView(
                                    displayName: entry.profile.displayName,
                                    username: entry.profile.username,
                                    avatarURL: entry.profile.avatarURL,
                                    avatarSize: 44
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                searchHistoryStore.remove(entry.id)
                            } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppStrings.localized("explore.remove_recent_search"))
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(16)
        }
    }

    private func loadMoreIfNeeded(afterDisplaying item: CommunityFeedItem, in items: [CommunityFeedItem]) {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            feedStore.canLoadMore,
            let triggerID = items.dropLast(2).last?.id,
            item.id == triggerID
        else { return }
        Task { await feedStore.loadMore() }
    }

    private var searchDismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // A content-upward swipe is the conventional direction for
                // dismissing search. It remains simultaneous with scrolling.
                guard value.translation.height < -12 else { return }
                dismissSearch()
            }
    }

    private func dismissSearch() {
        guard isSearchFocused else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchFocused = false
        }
    }

    private func cancelSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            query = ""
            isSearchFocused = false
        }
        searchStore.clear()
        searchPostItems = []
        feedStore.clearHashtagPosts()
    }
}
