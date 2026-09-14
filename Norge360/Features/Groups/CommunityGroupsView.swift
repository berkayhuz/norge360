import PhotosUI
import SwiftUI

// Group discovery, detail and management are one authorization-sensitive
// vertical slice; splitting them would separate their role checks from UI.
// swiftlint:disable file_length

struct CommunityGroupsView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    let usesEmbeddedChrome: Bool
    let tracksTabBarScroll: Bool
    @State private var isPresentingCreateGroup = false
    @State private var searchText = ""
    @State private var scopeFilter: GroupScopeFilter = .all
    @State private var visibilityFilter: GroupVisibilityFilter = .all
    @State private var isPresentingFilters = false
    @State private var selectedGroup: CommunityGroup?

    init(usesEmbeddedChrome: Bool = false, tracksTabBarScroll: Bool = true) {
        self.usesEmbeddedChrome = usesEmbeddedChrome
        self.tracksTabBarScroll = tracksTabBarScroll
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupsStore.isLoading && groupsStore.groups.isEmpty {
                    NorgeLoadingState()
                } else if groupsStore.groups.isEmpty
                    && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    NorgeUnavailableState(
                        AppStrings.localized("groups.empty_title"),
                        systemImage: "person.3",
                        description: AppStrings.localized("groups.empty_body")
                    )
                } else {
                    let joinedGroups = filteredGroups(
                        groupsStore.groups.filter { groupsStore.joinedGroupIDs.contains($0.id) })
                    let discoverableGroups = filteredGroups(
                        groupsStore.groups.filter { !groupsStore.joinedGroupIDs.contains($0.id) })

                    ScrollViewReader { proxy in
                        List {
                            if groupsStore.errorMessage != nil {
                                Section {
                                    NorgeInlineFeedback(message: AppStrings.localized("groups.error"))
                                }
                                .listRowBackground(Color.norgeAppBackground)
                            }

                            GroupSectionHeader(
                                title: joinedGroups.isEmpty
                                    ? AppStrings.localized("groups.discover")
                                    : AppStrings.localized("groups.yours"),
                                searchText: $searchText,
                                onFilter: { isPresentingFilters = true }
                            )
                            .listRowBackground(Color.norgeAppBackground)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0, leading: NorgeSpacing.medium, bottom: 8, trailing: NorgeSpacing.medium)
                            )
                            .id("community-groups-top")
                            .overlay {
                                if tracksTabBarScroll {
                                    ScrollHeaderVisibilityObserver { visible in
                                        tabRouter.setTabBarCompact(!visible, for: .community)
                                    }
                                    .frame(width: 1, height: 1)
                                    .allowsHitTesting(false)
                                }
                            }

                            if !joinedGroups.isEmpty {
                                Section {
                                    ForEach(joinedGroups) { group in
                                        CommunityGroupRow(
                                            group: group,
                                            isJoined: true,
                                            isOwner: groupsStore.ownedGroupIDs.contains(group.id),
                                            isPending: false,
                                            isUpdating: groupsStore.updatingGroupIDs.contains(group.id),
                                            onOpen: { selectedGroup = group },
                                            onToggle: { await groupsStore.toggleMembership(for: group) },
                                            onCancelRequest: {}
                                        )
                                    }
                                }
                                .listRowBackground(Color.norgeAppBackground)
                            }

                            if !joinedGroups.isEmpty {
                                HStack {
                                    Text(AppStrings.localized("groups.more"))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button {
                                        isPresentingFilters = true
                                    } label: {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                            .font(.title3.weight(.semibold))
                                            .frame(width: 40, height: 40)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(AppStrings.localized("groups.filter"))
                                }
                                .textCase(nil)
                                .listRowBackground(Color.norgeAppBackground)
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 8, leading: NorgeSpacing.medium, bottom: 0, trailing: NorgeSpacing.medium))
                            }

                            Section {
                                if discoverableGroups.isEmpty {
                                    NorgeUnavailableState(
                                        AppStrings.localized("groups.empty_title"),
                                        systemImage: "person.3",
                                        description: AppStrings.localized("groups.empty_body")
                                    )
                                    .frame(maxWidth: .infinity)
                                } else {
                                    ForEach(discoverableGroups) { group in
                                        CommunityGroupRow(
                                            group: group,
                                            isJoined: false,
                                            isOwner: false,
                                            isPending: groupsStore.pendingJoinGroupIDs.contains(group.id),
                                            isUpdating: groupsStore.updatingGroupIDs.contains(group.id),
                                            onOpen: { selectedGroup = group },
                                            onToggle: { await groupsStore.toggleMembership(for: group) },
                                            onCancelRequest: { await groupsStore.cancelJoinRequest(for: group.id) }
                                        )
                                    }
                                }
                                if groupsStore.canLoadMore {
                                    GroupPaginationFooter(isLoading: groupsStore.isLoadingMore)
                                        .task {
                                            await groupsStore.loadMore(searchQuery: searchText)
                                        }
                                }
                            }
                            .listRowBackground(Color.norgeAppBackground)
                        }
                        .listStyle(.plain)
                        .contentMargins(.top, 0, for: .scrollContent)
                        .listRowSeparator(.hidden)
                        .onChange(of: tabRouter.communityScrollToTopToken) { _, _ in
                            withAnimation(.easeOut(duration: 0.24)) {
                                proxy.scrollTo("community-groups-top", anchor: .top)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .presentationBackground(Color.norgeAppBackground)
            .toolbar(usesEmbeddedChrome ? .hidden : .visible, for: .navigationBar)
            .navigationTitle(AppStrings.localized("feed.groups"))
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedGroup != nil },
                    set: { if !$0 { selectedGroup = nil } }
                )
            ) {
                if let selectedGroup {
                    CommunityGroupDetailView(group: selectedGroup)
                }
            }
            .toolbar {
                if !usesEmbeddedChrome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingCreateGroup = true
                        } label: {
                            NorgeTopBarActionLabel(systemName: "plus")
                        }
                        .accessibilityLabel(AppStrings.localized("groups.create"))
                    }
                    .norgePlainToolbar()
                }
            }
            .refreshable { await groupsStore.reload(searchQuery: searchText) }
            .task(id: searchText) {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    await groupsStore.loadIfNeeded(searchQuery: searchText)
                } catch {
                    // A new keystroke cancels the previous search task.
                }
            }
            .sheet(isPresented: $isPresentingCreateGroup) { CreateCommunityGroupView() }
            .sheet(isPresented: $isPresentingFilters) {
                GroupFiltersView(scope: $scopeFilter, visibility: $visibilityFilter)
                    .presentationDetents([.medium])
            }
        }
    }

    private func filteredGroups(_ groups: [CommunityGroup]) -> [CommunityGroup] {
        groups.filter { group in
            let matchesScope = scopeFilter.matches(group.scope)
            let matchesVisibility = visibilityFilter.matches(group.visibility)
            return matchesScope && matchesVisibility
        }
    }
}

private struct GroupSectionHeader: View {
    let title: String
    @Binding var searchText: String
    let onFilter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(AppStrings.localized("groups.search"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color.norgeInputSurface, in: Capsule())
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: onFilter) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("groups.filter"))
            }
        }
        .textCase(nil)
    }
}

private struct GroupPaginationFooter: View {
    let isLoading: Bool

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                NorgeSkeleton(width: 180, height: 12)
            }
            Spacer()
        }
        .frame(height: 44)
        .listRowBackground(Color.norgeAppBackground)
        .listRowSeparator(.hidden)
    }
}

private enum GroupScopeFilter: String, CaseIterable, Identifiable {
    case all
    case city
    case interest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.localized("groups.filter_all")
        case .city: AppStrings.localized("groups.scope_city")
        case .interest: AppStrings.localized("groups.scope_interest")
        }
    }

    func matches(_ scope: CommunityGroupScope) -> Bool {
        switch self {
        case .all: true
        case .city: scope == .city
        case .interest: scope == .interest
        }
    }
}

private enum GroupVisibilityFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case approval
    case privateGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.localized("groups.filter_all")
        case .open: AppStrings.localized("groups.anyone_can_join")
        case .approval: AppStrings.localized("groups.approval_required")
        case .privateGroup: AppStrings.localized("groups.private")
        }
    }

    func matches(_ visibility: CommunityGroupVisibility) -> Bool {
        switch self {
        case .all: true
        case .open: visibility == .public
        case .approval: visibility == .approvalRequired
        case .privateGroup: visibility == .private
        }
    }
}

private struct GroupFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scope: GroupScopeFilter
    @Binding var visibility: GroupVisibilityFilter

    var body: some View {
        NavigationStack {
            Form {
                Picker(AppStrings.localized("groups.filter_scope"), selection: $scope) {
                    ForEach(GroupScopeFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker(AppStrings.localized("groups.filter_visibility"), selection: $visibility) {
                    ForEach(GroupVisibilityFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            .norgeScreen()
            .navigationTitle(AppStrings.localized("groups.filter"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("groups.save")) { dismiss() }
                }
                .norgePlainToolbar()
            }
        }
    }
}

struct CreateCommunityGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @State private var name = ""
    @State private var slug = ""
    @State private var description = ""
    @State private var scope: CommunityGroupScope = .interest
    @State private var visibility: CommunityGroupVisibility = .public
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppStrings.localized("groups.name"), text: $name)
                        .onChange(of: name) { _, value in if slug.isEmpty { slug = slugify(value) } }
                    TextField(AppStrings.localized("groups.slug"), text: $slug)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    ZStack(alignment: .topLeading) {
                        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(AppStrings.localized("groups.description_placeholder"))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $description)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                    }
                }
                .listRowBackground(Color.norgeAppBackground)
                Picker(AppStrings.localized("groups.scope"), selection: $scope) {
                    Text(AppStrings.localized("groups.scope_interest")).tag(CommunityGroupScope.interest)
                    Text(AppStrings.localized("groups.scope_city")).tag(CommunityGroupScope.city)
                }
                Picker(AppStrings.localized("groups.joining"), selection: $visibility) {
                    Text(AppStrings.localized("groups.anyone_can_join")).tag(CommunityGroupVisibility.public)
                    Text(AppStrings.localized("groups.approval_required")).tag(
                        CommunityGroupVisibility.approvalRequired)
                    Text(AppStrings.localized("groups.private")).tag(CommunityGroupVisibility.private)
                }
                if let errorMessage { NorgeInlineFeedback(message: errorMessage) }
            }
            .listStyle(.insetGrouped)
            .norgeScreen()
            .navigationTitle(AppStrings.localized("groups.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        NorgeTopBarActionLabel(systemName: "plus")
                    }
                    .accessibilityLabel(AppStrings.localized("groups.create"))
                    .disabled(!isValid || isCreating)
                }
                .norgePlainToolbar()
            }
        }
    }

    private var isValid: Bool { CommunityGroupRules.isValid(name: name, slug: slug, description: description) }
    private func slugify(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(
            separator: "-")
    }
    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            try await groupsStore.create(
                draft: CommunityGroupDraft(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines), slug: slug,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope,
                    cityOrRegion: nil, visibility: visibility))
            dismiss()
        } catch { errorMessage = AppStrings.localized("groups.create_error") }
    }
}

private struct CommunityGroupMemberInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    let groupID: UUID
    let groupName: String
    @State private var query = ""
    @State private var sendingIDs: Set<UUID> = []
    @State private var sentIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(AppStrings.localized("invites.search_hint"), text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Section { NorgeInlineFeedback(message: errorMessage) }
                }
                Section {
                    ForEach(results) { profile in
                        HStack(spacing: 12) {
                            CommunityAvatarView(url: profile.avatarURL, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(.body.weight(.semibold))
                                Text("@\(profile.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await invite(profile) }
                            } label: {
                                Text(
                                    sentIDs.contains(profile.userID)
                                        ? AppStrings.localized("invites.sent")
                                        : AppStrings.localized("invites.send"))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(sentIDs.contains(profile.userID) || sendingIDs.contains(profile.userID))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .norgeScreen()
            .navigationTitle(String(format: AppStrings.localized("groups.invite_members_title"), groupName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
            }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
                        searchStore.clear()
                        return
                    }
                    await searchStore.search(query: query)
                } catch {
                    // A new keystroke cancels the previous search task.
                }
            }
        }
    }

    private var results: [CommunityProfile] {
        searchStore.results.profiles.filter { $0.userID != authenticationStore.user?.id }
    }

    private func invite(_ profile: CommunityProfile) async {
        sendingIDs.insert(profile.userID)
        errorMessage = nil
        defer { sendingIDs.remove(profile.userID) }
        do {
            try await groupsStore.inviteMember(groupID: groupID, userID: profile.userID)
            sentIDs.insert(profile.userID)
        } catch {
            errorMessage = AppStrings.localized("invites.error")
        }
    }
}

private struct CommunityGroupRow: View {
    let group: CommunityGroup
    let isJoined: Bool
    let isOwner: Bool
    let isPending: Bool
    let isUpdating: Bool
    let onOpen: () -> Void
    let onToggle: () async -> Void
    let onCancelRequest: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CommunityGroupImageView(
                    photoURL: group.photoURL,
                    isCityGroup: group.scope == .city,
                    isDecorative: false
                )

                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onOpen) {
                        Text(group.name).font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Text(group.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                if isOwner {
                    NorgeMetadataLabel(title: AppStrings.localized("groups.admin"), systemImage: "crown")
                } else if isPending {
                    Button(AppStrings.localized("groups.cancel_request")) {
                        Task { await onCancelRequest() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUpdating)
                    .accessibilityLabel("\(AppStrings.localized("groups.cancel_request")) \(group.name)")
                } else {
                    Button(membershipButtonTitle) {
                        Task { await onToggle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isJoined ? .secondary : .norgePrimary)
                    .controlSize(.small)
                    .disabled(isUpdating)
                    .accessibilityLabel("\(membershipButtonTitle) \(group.name)")
                }
            }
            if let cityOrRegion = group.cityOrRegion {
                NorgeMetadataLabel(title: cityOrRegion, systemImage: "mappin.and.ellipse")
            }
        }
        .padding(.vertical, 4)
    }

    private var membershipButtonTitle: String {
        if isJoined { return AppStrings.localized("groups.leave") }
        return group.visibility != .public
            ? AppStrings.localized("groups.request_to_join")
            : AppStrings.localized("groups.join")
    }
}

struct CommunityGroupDetailView: View {
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var group: CommunityGroup
    @State private var members: [CommunityGroupMembership] = []
    @State private var profiles: [UUID: CommunityProfile] = [:]
    @State private var errorMessage: String?
    @State private var postingPermission: CommunityGroupPostingPermission = .members
    @State private var visibility: CommunityGroupVisibility = .public
    @State private var joinRequests: [CommunityGroupJoinRequest] = []
    @State private var bans: [CommunityGroupBan] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pendingPhoto: CommunityImageDraft?
    @State private var photoURL: URL?
    @State private var isUpdatingPhoto = false
    @State private var posts: [CommunityFeedItem] = []
    @State private var nextPostsCursor: String?
    @State private var isLoadingMorePosts = false
    @State private var isLoadingPosts = true
    @State private var isPresentingComposer = false
    @State private var postPendingRemoval: CommunityFeedItem?
    @State private var isPresentingDetailsEditor = false
    @State private var ownershipTransferTarget: CommunityGroupMembership?
    @State private var isPresentingGroupReport = false
    @State private var reportNoticeMessage: String?
    @State private var isPresentingMemberInvite = false

    init(group: CommunityGroup) {
        _group = State(initialValue: group)
    }

}

extension CommunityGroupDetailView {
    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottomTrailing) {
                    CommunityGroupImageView(
                        photoURL: photoURL ?? group.photoURL,
                        isCityGroup: group.scope == .city,
                        width: nil,
                        height: 180,
                        shape: .roundedRectangle(14),
                        isDecorative: false
                    )
                    .frame(height: 180)

                    if canUpdatePhoto {
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Image(systemName: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.norgePrimary, in: Circle())
                        }
                        .disabled(isUpdatingPhoto)
                        .padding(12)
                        .accessibilityLabel(AppStrings.localized("groups.change_photo"))
                    }
                }
                .listRowInsets(EdgeInsets())
                .accessibilityElement(children: .combine)

                Text(group.description)
                if currentRole == nil {
                    Button {
                        Task { await groupsStore.toggleMembership(for: group) }
                    } label: {
                        Label(
                            groupsStore.pendingJoinGroupIDs.contains(group.id)
                                ? AppStrings.localized("groups.cancel_request")
                                : membershipActionTitle,
                            systemImage: groupsStore.pendingJoinGroupIDs.contains(group.id)
                                ? "xmark" : "person.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(groupsStore.pendingJoinGroupIDs.contains(group.id) ? .secondary : .norgePrimary)
                    .disabled(groupsStore.updatingGroupIDs.contains(group.id))
                }
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("groups.posts")) {
                if isLoadingPosts {
                    NorgeLoadingState()
                } else if posts.isEmpty {
                    NorgeUnavailableState(
                        AppStrings.localized("groups.posts_empty_title"),
                        systemImage: "rectangle.stack",
                        description: AppStrings.localized("groups.posts_empty_body")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(posts) { item in
                        CommunityFeedPostView(item: item)
                            .listRowInsets(NorgeLayoutMetrics.standardListRowInset)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                guard item.id == posts.last?.id else { return }
                                Task { await loadMorePosts() }
                            }
                            .contextMenu {
                                if canModeratePosts {
                                    Button(
                                        AppStrings.localized("groups.remove_post"), systemImage: "trash",
                                        role: .destructive
                                    ) {
                                        postPendingRemoval = item
                                    }
                                }
                            }
                    }
                }
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("events.group_title")) {
                NavigationLink {
                    CommunityEventsView(group: group, canCreateGroupEvent: isGroupStaff)
                } label: {
                    Label(AppStrings.localized("events.open_group_events"), systemImage: "calendar")
                }
            }
            .listRowBackground(Color.norgeAppBackground)
            if currentRole != nil {
                Section(AppStrings.localized("groups.chat")) {
                    NavigationLink {
                        CommunityGroupChatView(group: group)
                    } label: {
                        Label(AppStrings.localized("groups.open_chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .listRowBackground(Color.norgeAppBackground)
            }
            if currentRole == "owner" || currentRole == "admin" {
                Section(AppStrings.localized("groups.posting_permission")) {
                    Picker(AppStrings.localized("groups.who_can_post"), selection: $postingPermission) {
                        Text(AppStrings.localized("groups.posting_members")).tag(
                            CommunityGroupPostingPermission.members)
                        Text(AppStrings.localized("groups.posting_staff")).tag(
                            CommunityGroupPostingPermission.moderatorsAndAbove)
                    }
                    .onChange(of: postingPermission) { _, value in Task { await updatePostingPermission(value) } }
                }
                .listRowBackground(Color.norgeAppBackground)
                Section(AppStrings.localized("groups.joining")) {
                    Picker(AppStrings.localized("groups.joining"), selection: $visibility) {
                        Text(AppStrings.localized("groups.anyone_can_join")).tag(CommunityGroupVisibility.public)
                        Text(AppStrings.localized("groups.approval_required")).tag(
                            CommunityGroupVisibility.approvalRequired)
                        Text(AppStrings.localized("groups.private")).tag(CommunityGroupVisibility.private)
                    }
                    .onChange(of: visibility) { _, value in Task { await updateVisibility(value) } }

                    if visibility != .public {
                        if joinRequests.isEmpty {
                            Text(AppStrings.localized("groups.no_join_requests"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(joinRequests) { request in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.displayName)
                                        if let username = request.username {
                                            Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Menu {
                                        Button(AppStrings.localized("groups.approve_request")) {
                                            Task { await review(request, decision: "approved") }
                                        }
                                        Button(AppStrings.localized("groups.decline_request"), role: .destructive) {
                                            Task { await review(request, decision: "rejected") }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .accessibilityLabel(AppStrings.localized("groups.review_request"))
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.norgeAppBackground)
                Section(AppStrings.localized("groups.banned_members")) {
                    if bans.isEmpty {
                        Text(AppStrings.localized("groups.no_banned_members"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bans) { ban in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ban.displayName)
                                    if let username = ban.username {
                                        Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(AppStrings.localized("groups.unban")) {
                                    Task { await unban(ban) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .listRowBackground(Color.norgeAppBackground)
            }
            Section(AppStrings.localized("groups.members")) {
                ForEach(members) { member in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profiles[member.userID]?.displayName ?? AppStrings.localized("feed.member"))
                            Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if canManage(member) {
                            Menu {
                                Button(AppStrings.localized("groups.make_member")) {
                                    Task { await manage(member, action: "set_role", role: "member") }
                                }
                                if currentRole == "owner" {
                                    Button(AppStrings.localized("groups.make_moderator")) {
                                        Task { await manage(member, action: "set_role", role: "moderator") }
                                    }
                                    Button(AppStrings.localized("groups.make_admin")) {
                                        Task { await manage(member, action: "set_role", role: "admin") }
                                    }
                                }
                                if CommunityGroupManagementRules.canTransferOwnership(
                                    actorRole: currentRole, targetRole: member.role,
                                    isSelfTarget: member.userID == authenticationStore.user?.id)
                                {
                                    Button(AppStrings.localized("groups.transfer_ownership"), role: .destructive) {
                                        ownershipTransferTarget = member
                                    }
                                }
                                Button(AppStrings.localized("groups.remove_member"), role: .destructive) {
                                    Task { await manage(member, action: "remove", role: nil) }
                                }
                                Button(AppStrings.localized("groups.ban_member"), role: .destructive) {
                                    Task { await ban(member) }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.norgeAppBackground)
            if let errorMessage { NorgeInlineFeedback(message: errorMessage) }
            if let reportNoticeMessage { Text(reportNoticeMessage).foregroundStyle(.green) }
        }
        .norgeScreen()
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if canInviteMembers {
                        Button {
                            isPresentingMemberInvite = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 36, height: 44)
                        }
                        .accessibilityLabel(AppStrings.localized("groups.invite_members"))
                    }
                    if !isGroupStaff {
                        Button {
                            isPresentingGroupReport = true
                        } label: {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 36, height: 44)
                        }
                        .accessibilityLabel(AppStrings.localized("groups.report"))
                    }
                    if currentRole == "owner" || currentRole == "admin" {
                        Button {
                            isPresentingDetailsEditor = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 36, height: 44)
                        }
                        .accessibilityLabel(AppStrings.localized("groups.edit_details"))
                    }
                    if canCreatePost {
                        Button {
                            isPresentingComposer = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 36, height: 44)
                        }
                        .accessibilityLabel(AppStrings.localized("groups.new_post"))
                    }
                }
            }
            .norgePlainToolbar()
        }
        .task { await load() }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CommunityMediaError.unsupportedImage
                    }
                    pendingPhoto = CommunityImageDraft(data: data, aspect: .cover)
                } catch { errorMessage = AppStrings.localized("groups.photo_error") }
                photoPickerItem = nil
            }
        }
        .sheet(item: $pendingPhoto) { draft in
            CommunityImageEditor(source: draft) { data in await updatePhoto(data: data) }
        }
        .sheet(
            isPresented: $isPresentingComposer,
            onDismiss: {
                Task { await loadPosts() }
            },
            content: {
                CreateCommunityPostView(
                    joinedGroups: [group],
                    initialDestination: .group(group.id)
                )
            }
        )
        .sheet(isPresented: $isPresentingDetailsEditor) {
            EditCommunityGroupDetailsView(group: group) { updatedGroup in
                group = updatedGroup
            }
        }
        .sheet(isPresented: $isPresentingMemberInvite) {
            CommunityGroupMemberInviteView(groupID: group.id, groupName: group.name)
        }
        .alert(
            AppStrings.localized("groups.remove_post_title"),
            isPresented: Binding(
                get: { postPendingRemoval != nil },
                set: { if !$0 { postPendingRemoval = nil } }
            ),
            presenting: postPendingRemoval
        ) { item in
            Button(AppStrings.localized("groups.remove_post"), role: .destructive) {
                Task { await remove(item) }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { postPendingRemoval = nil }
        } message: { _ in
            Text(AppStrings.localized("groups.remove_post_body"))
        }
        .alert(
            AppStrings.localized("groups.transfer_ownership_title"),
            isPresented: Binding(
                get: { ownershipTransferTarget != nil },
                set: { if !$0 { ownershipTransferTarget = nil } }
            ),
            presenting: ownershipTransferTarget
        ) { member in
            Button(AppStrings.localized("groups.transfer_ownership"), role: .destructive) {
                Task { await transferOwnership(to: member) }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { ownershipTransferTarget = nil }
        } message: { member in
            Text(
                String(
                    format: AppStrings.localized("groups.transfer_ownership_body"),
                    profiles[member.userID]?.displayName ?? AppStrings.localized("feed.member")))
        }
        .confirmationDialog(
            AppStrings.localized("groups.report_title"),
            isPresented: $isPresentingGroupReport,
            titleVisibility: .visible
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    Task {
                        if await feedStore.report(groupID: group.id, reason: reason) {
                            reportNoticeMessage = AppStrings.localized("feed.report_sent")
                        } else {
                            errorMessage = AppStrings.localized("feed.report_error")
                        }
                    }
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("groups.report_body"))
        }
    }

    private var currentRole: String? { members.first { $0.userID == authenticationStore.user?.id }?.role }
    private var membershipActionTitle: String {
        group.visibility == .public
            ? AppStrings.localized("groups.join")
            : AppStrings.localized("groups.request_to_join")
    }
    private var isGroupStaff: Bool { ["owner", "admin", "moderator"].contains(currentRole) }
    private var canInviteMembers: Bool { ["owner", "admin"].contains(currentRole) }
    private var canUpdatePhoto: Bool { ["owner", "admin", "moderator"].contains(currentRole) }
    private var canCreatePost: Bool {
        guard let role = currentRole else { return false }
        return postingPermission == .members || ["owner", "admin", "moderator"].contains(role)
    }
    private var canModeratePosts: Bool { ["owner", "admin", "moderator"].contains(currentRole) }
    private func canManage(_ member: CommunityGroupMembership) -> Bool {
        guard let role = currentRole, member.userID != authenticationStore.user?.id else { return false }
        return role == "owner" || (role == "admin" && member.role == "member")
    }
    private func load() async {
        do {
            async let membersRequest = groupsStore.members(for: group.id)
            async let postsRequest = feedStore.groupPosts(for: group.id)
            let (loadedMembers, loadedPage) = try await (membersRequest, postsRequest)
            members = loadedMembers
            posts = loadedPage.items
            nextPostsCursor = loadedPage.nextCursor
            isLoadingPosts = false
            postingPermission = group.postingPermission
            visibility = group.visibility
            photoURL = group.photoURL
            let items = try await groupsStore.memberProfiles(for: members.map(\.userID))
            profiles = Dictionary(uniqueKeysWithValues: items.map { ($0.userID, $0) })
            if currentRole == "owner" || currentRole == "admin" {
                joinRequests = try await groupsStore.joinRequests(for: group.id)
                bans = try await groupsStore.bans(for: group.id)
            }
        } catch {
            isLoadingPosts = false
            errorMessage = AppStrings.localized("groups.members_error")
        }
    }
    private func loadPosts() async {
        isLoadingPosts = true
        defer { isLoadingPosts = false }
        do {
            let page = try await feedStore.groupPosts(for: group.id)
            posts = page.items
            nextPostsCursor = page.nextCursor
        } catch {
            errorMessage = AppStrings.localized("groups.posts_error")
        }
    }

    private func loadMorePosts() async {
        guard !isLoadingMorePosts, let nextPostsCursor else { return }
        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }
        do {
            let page = try await feedStore.groupPosts(for: group.id, cursor: nextPostsCursor)
            let existingIDs = Set(posts.map(\.id))
            posts.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            self.nextPostsCursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppStrings.localized("groups.posts_error")
        }
    }
    private func manage(_ member: CommunityGroupMembership, action: String, role: String?) async {
        do {
            try await groupsStore.manageMember(groupID: group.id, userID: member.userID, action: action, role: role)
            await load()
        } catch { errorMessage = AppStrings.localized("groups.manage_error") }
    }
    private func updatePostingPermission(_ value: CommunityGroupPostingPermission) async {
        do { try await groupsStore.updatePostingPermission(groupID: group.id, permission: value) } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
            postingPermission = group.postingPermission
        }
    }
    private func updateVisibility(_ value: CommunityGroupVisibility) async {
        do {
            try await groupsStore.updateVisibility(groupID: group.id, visibility: value)
            if value != .public { joinRequests = try await groupsStore.joinRequests(for: group.id) }
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
            visibility = group.visibility
        }
    }
    private func review(_ request: CommunityGroupJoinRequest, decision: String) async {
        do {
            try await groupsStore.reviewJoinRequest(groupID: group.id, userID: request.userID, decision: decision)
            joinRequests.removeAll { $0.id == request.id }
            if decision == "approved" { await load() }
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
        }
    }
    private func ban(_ member: CommunityGroupMembership) async {
        do {
            try await groupsStore.banMember(groupID: group.id, userID: member.userID)
            await load()
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
        }
    }
    private func unban(_ ban: CommunityGroupBan) async {
        do {
            try await groupsStore.unbanMember(groupID: group.id, userID: ban.userID)
            bans.removeAll { $0.id == ban.id }
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
        }
    }
    private func remove(_ item: CommunityFeedItem) async {
        do {
            try await feedStore.removeGroupPost(id: item.post.id, groupID: group.id)
            posts.removeAll { $0.post.id == item.post.id }
            postPendingRemoval = nil
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
        }
    }
    private func transferOwnership(to member: CommunityGroupMembership) async {
        do {
            try await groupsStore.transferOwnership(groupID: group.id, userID: member.userID)
            ownershipTransferTarget = nil
            await load()
        } catch {
            errorMessage = AppStrings.localized("groups.manage_error")
        }
    }
    private func updatePhoto(data: Data) async {
        isUpdatingPhoto = true
        defer {
            isUpdatingPhoto = false
            photoPickerItem = nil
        }

        do {
            let image = try await CommunityImageProcessing.prepareJPEG(from: data)
            try await groupsStore.updatePhoto(groupID: group.id, image: image)
            photoURL = groupsStore.groups.first(where: { $0.id == group.id })?.photoURL
        } catch {
            errorMessage = AppStrings.localized("groups.photo_error")
        }
    }
}

private struct EditCommunityGroupDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    let group: CommunityGroup
    let onSaved: (CommunityGroup) -> Void

    @State private var name: String
    @State private var slug: String
    @State private var description: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(group: CommunityGroup, onSaved: @escaping (CommunityGroup) -> Void) {
        self.group = group
        self.onSaved = onSaved
        _name = State(initialValue: group.name)
        _slug = State(initialValue: group.slug)
        _description = State(initialValue: group.description)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(AppStrings.localized("groups.name"), text: $name)
                TextField(AppStrings.localized("groups.slug"), text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextEditor(text: $description)
                    .frame(minHeight: 120)
                    .accessibilityLabel(AppStrings.localized("groups.description"))
                if let errorMessage {
                    NorgeInlineFeedback(message: errorMessage)
                }
            }
            .norgeScreen()
            .navigationTitle(AppStrings.localized("groups.edit_details"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("groups.save")) { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
                .norgePlainToolbar()
            }
        }
    }

    private var isValid: Bool { CommunityGroupRules.isValid(name: name, slug: slug, description: description) }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updatedGroup = try await groupsStore.updateDetails(
                groupID: group.id,
                draft: CommunityGroupDetailsDraft(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    slug: slug.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            onSaved(updatedGroup)
            dismiss()
        } catch {
            errorMessage = AppStrings.localized("groups.details_error")
        }
    }
}
