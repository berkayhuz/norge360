import SwiftUI
import UIKit

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
    @State private var searchRequestGeneration = 0
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var searchHistoryStore: CommunitySearchHistoryStore

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
                            NorgeLoadingState(minimumHeight: 240)
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
                        NorgeLoadingState(fillsAvailableSpace: true)
                    } else {
                        postResults(displayedPosts)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .presentationBackground(Color.norgeAppBackground)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await feedStore.activate()
                await groupsStore.activate()
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
                searchPostItems = searchStore.results.postItems
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
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("explore-top")
                    ScrollHeaderVisibilityObserver { visible in
                        tabRouter.setTabBarCompact(!visible, for: .explore)
                    }
                    .frame(height: 0)
                    postResultList(posts, emptyTitle: emptyTitle)
                        .padding(.horizontal, NorgeSpacing.medium)
                        .padding(.bottom, NorgeSpacing.medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 0, for: .scrollContent)
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

    @ViewBuilder
    private func postResultList(_ posts: [CommunityFeedItem], emptyTitle: String?) -> some View {
        LazyVStack(alignment: .leading, spacing: NorgeLayoutMetrics.feedItemSpacing) {
            if let error = feedStore.errorMessage {
                NorgeInlineFeedback(message: error)
            }
            if posts.isEmpty {
                NorgeUnavailableState(
                    emptyTitle ?? AppStrings.localized("explore.empty_title"),
                    systemImage: "rectangle.stack",
                    description: AppStrings.localized("explore.empty_body"))
            }
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
                NorgeSkeletonList(rowCount: 1)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searchStore.isSearching {
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
                VStack(alignment: .leading, spacing: 0) {
                    ScrollHeaderVisibilityObserver { visible in
                        tabRouter.setTabBarCompact(!visible, for: .explore)
                    }
                    .frame(height: 0)
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !searchStore.results.profiles.isEmpty {
                            sectionTitle("explore.people")
                            ForEach(searchStore.results.profiles) { profile in
                                Button {
                                    dismissKeyboardForNavigation()
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(searchDismissDrag)
        }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(AppStrings.localized(key)).font(.title3.weight(.bold))
    }

    private var recentSearches: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollHeaderVisibilityObserver { visible in
                    tabRouter.setTabBarCompact(!visible, for: .explore)
                }
                .frame(height: 0)
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
                                    dismissKeyboardForNavigation()
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
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.top, 0, for: .scrollContent)
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
        dismissKeyboardForNavigation()
    }

    private func dismissKeyboardForNavigation() {
        isSearchFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
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
