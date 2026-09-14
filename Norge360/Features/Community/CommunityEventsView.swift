import PhotosUI
import SwiftUI
import UIKit

// Event list, RSVP and event creation form one complete community slice.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct CommunityEventsView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    let group: CommunityGroup?
    let canCreateGroupEvent: Bool
    let showsLikedOnly: Bool
    let usesEmbeddedChrome: Bool
    let tracksTabBarScroll: Bool
    let focusedEventID: UUID?
    @State private var sort: EventSort = .hot
    @State private var isPresentingCreate = false
    @State private var deleteTarget: CommunityEventItem?
    @State private var reportTarget: CommunityEventItem?
    @State private var blockTarget: CommunityEventItem?
    @State private var inviteTarget: CommunityEventItem?
    @State private var searchText = ""
    @State private var eventFilter: EventFilter = .all
    @State private var isPresentingFilters = false
    @State private var selectedCountyCode: String?
    @State private var selectedMunicipalityCode: String?

    init(
        group: CommunityGroup? = nil,
        canCreateGroupEvent: Bool = true,
        showsLikedOnly: Bool = false,
        usesEmbeddedChrome: Bool = false,
        tracksTabBarScroll: Bool = true,
        focusedEventID: UUID? = nil
    ) {
        self.group = group
        self.canCreateGroupEvent = canCreateGroupEvent
        self.showsLikedOnly = showsLikedOnly
        self.usesEmbeddedChrome = usesEmbeddedChrome
        self.tracksTabBarScroll = tracksTabBarScroll
        self.focusedEventID = focusedEventID
    }

    var body: some View {
        Group {
            if eventsStore.isLoading && eventsStore.items.isEmpty {
                NorgeLoadingState(fillsAvailableSpace: true)
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    TextField(AppStrings.localized("events.search"), text: $searchText)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                                .norgeCapsuleInput(height: 40, horizontalPadding: 12)
                                Button {
                                    isPresentingFilters = true
                                } label: {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.title3.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AppStrings.localized("events.filter"))
                            }
                            .id("community-events-top")
                            .overlay {
                                if tracksTabBarScroll {
                                    ScrollHeaderVisibilityObserver { visible in
                                        tabRouter.setTabBarCompact(!visible, for: .community)
                                    }
                                    .frame(width: 1, height: 1)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                        .listRowBackground(Color.norgeAppBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: NorgeSpacing.medium, bottom: 4, trailing: NorgeSpacing.medium))
                        if let errorMessage = eventsStore.errorMessage {
                            NorgeFormErrorSection(message: errorMessage)
                        }
                        if displayedItems.isEmpty {
                            Section {
                                NorgeUnavailableState(
                                    showsLikedOnly
                                        ? AppStrings.localized("events.likes_empty_title")
                                        : AppStrings.localized("events.empty_title"),
                                    systemImage: showsLikedOnly ? "heart" : "calendar",
                                    description: showsLikedOnly
                                        ? AppStrings.localized("events.likes_empty_body")
                                        : AppStrings.localized("events.empty_body")
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .listRowBackground(Color.norgeAppBackground)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(displayedItems) { item in
                                CommunityEventRow(
                                    item: item,
                                    isUpdating: eventsStore.updatingEventIDs.contains(item.id),
                                    isOwnEvent: item.event.hostID == authenticationStore.user?.id,
                                    onRSVP: { status in await eventsStore.setRSVP(eventID: item.id, status: status) },
                                    onLike: { liked in await eventsStore.setLiked(eventID: item.id, isLiked: liked) },
                                    onRequestDelete: { deleteTarget = item },
                                    onReport: { reportTarget = item },
                                    onBlock: { blockTarget = item },
                                    onInvite: { inviteTarget = item }
                                )
                                .listRowBackground(Color.norgeAppBackground)
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: NorgeCornerRadius.smallCard, leading: NorgeSpacing.medium,
                                        bottom: NorgeCornerRadius.smallCard, trailing: NorgeSpacing.medium))
                            }
                        }
                        if eventsStore.canLoadMore {
                            EventPaginationFooter(isLoading: eventsStore.isLoadingMore)
                                .task {
                                    await eventsStore.loadMore(groupID: group?.id)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .onChange(of: tabRouter.communityScrollToTopToken) { _, _ in
                        withAnimation(.easeOut(duration: 0.24)) {
                            proxy.scrollTo("community-events-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.norgeAppBackground)
        .presentationBackground(Color.norgeAppBackground)
        .toolbar(usesEmbeddedChrome ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(
            usesEmbeddedChrome
                ? ""
                : (showsLikedOnly
                    ? AppStrings.localized("events.liked_title")
                    : (group == nil
                        ? AppStrings.localized("events.title") : AppStrings.localized("events.group_title")))
        )
        .toolbar {
            if !showsLikedOnly && (group == nil || canCreateGroupEvent) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingCreate = true
                    } label: {
                        NorgeTopBarActionLabel(systemName: "plus")
                    }
                    .accessibilityLabel(AppStrings.localized("events.create"))
                }
                .norgePlainToolbar()
            }
        }
        .task {
            // A hub tab switch must not recreate and reload this full screen.
            // Pull-to-refresh remains the explicit way to request fresh data.
            if focusedEventID != nil {
                await eventsStore.reload(groupID: group?.id, force: true)
            } else {
                await eventsStore.loadIfNeeded(groupID: group?.id)
            }
        }
        .refreshable { await eventsStore.reload(groupID: group?.id, force: true) }
        .sheet(isPresented: $isPresentingCreate) { CreateCommunityEventView(groupID: group?.id) }
        .sheet(isPresented: $isPresentingFilters) {
            EventFiltersView(
                selection: $eventFilter,
                sort: $sort,
                selectedCountyCode: $selectedCountyCode,
                selectedMunicipalityCode: $selectedMunicipalityCode
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $inviteTarget) { item in
            CommunityEventInviteView(eventID: item.id, eventTitle: item.event.title)
        }
        .confirmationDialog(
            AppStrings.localized("events.delete_title"),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("events.delete_confirm"), role: .destructive) {
                if let item = deleteTarget {
                    Task { await eventsStore.delete(eventID: item.id) }
                }
                deleteTarget = nil
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { deleteTarget = nil }
        } message: {
            Text(AppStrings.localized("events.delete_body"))
        }
        .confirmationDialog(
            AppStrings.localized("events.report_title"),
            isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    if let item = reportTarget { Task { await feedStore.report(eventID: item.id, reason: reason) } }
                    reportTarget = nil
                }
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { reportTarget = nil }
        } message: {
            Text(AppStrings.localized("feed.report_body"))
        }
        .alert(
            AppStrings.localized("feed.block_title"),
            isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
            presenting: blockTarget
        ) { item in
            Button(AppStrings.localized("feed.block_confirm"), role: .destructive) {
                Task {
                    _ = await feedStore.block(authorID: item.event.hostID)
                    await eventsStore.reload(groupID: group?.id)
                }
                blockTarget = nil
            }
            Button(AppStrings.localized("feed.cancel"), role: .cancel) { blockTarget = nil }
        } message: { item in
            Text(
                String(
                    format: AppStrings.localized("feed.block_body"),
                    item.host?.displayName ?? AppStrings.localized("feed.member")))
        }
    }

    private var filteredItems: [CommunityEventItem] {
        let source = showsLikedOnly ? eventsStore.items.filter(\.isLiked) : eventsStore.items
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { item in
            let matchesQuery =
                query.isEmpty
                || [
                    item.event.title,
                    item.event.details,
                    item.event.areaLabel,
                    item.event.venueName ?? "",
                    item.event.districtName ?? "",
                    item.event.neighborhoodName ?? "",
                    item.event.streetName ?? "",
                    item.event.category ?? "",
                    item.event.theme ?? "",
                ].contains {
                    $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            let matchesCounty = selectedCountyCode == nil || item.event.countyCode == selectedCountyCode
            let matchesMunicipality =
                selectedMunicipalityCode == nil || item.event.municipalityCode == selectedMunicipalityCode
            return matchesQuery && matchesCounty && matchesMunicipality && eventFilter.matches(item.event)
        }
    }

    private var displayedItems: [CommunityEventItem] {
        let source = filteredItems
        let sorted: [CommunityEventItem]
        switch sort {
        case .hot:
            sorted = source.sorted { lhs, rhs in
                if lhs.likeCount != rhs.likeCount { return lhs.likeCount > rhs.likeCount }
                return lhs.event.startsAt < rhs.event.startsAt
            }
        case .new:
            sorted = source.sorted { $0.event.createdAt > $1.event.createdAt }
        case .topToday:
            sorted = source.sorted { lhs, rhs in
                let lhsToday = Calendar.current.isDateInToday(lhs.event.startsAt)
                let rhsToday = Calendar.current.isDateInToday(rhs.event.startsAt)
                if lhsToday != rhsToday { return lhsToday }
                return lhs.likeCount > rhs.likeCount
            }
        case .latest:
            sorted = source.sorted { $0.event.startsAt < $1.event.startsAt }
        }
        guard let focusedEventID else { return sorted }
        return sorted.sorted { lhs, rhs in
            if lhs.id == focusedEventID { return true }
            if rhs.id == focusedEventID { return false }
            return false
        }
    }
}

private enum EventSort: String, CaseIterable, Identifiable {
    case hot, new, topToday, latest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hot: AppStrings.localized("events.sort.popular")
        case .new: AppStrings.localized("events.sort.recently_added")
        case .topToday: AppStrings.localized("events.sort.trending_today")
        case .latest: AppStrings.localized("events.sort.starting_soon")
        }
    }
    var symbol: String? {
        switch self {
        case .hot: "flame.fill"
        case .new: "clock.fill"
        case .topToday: "chart.bar.fill"
        case .latest: "clock.arrow.circlepath"
        }
    }
}

private enum EventFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek
    case limitedCapacity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.localized("events.filter_all")
        case .today: AppStrings.localized("events.filter_today")
        case .thisWeek: AppStrings.localized("events.filter_week")
        case .limitedCapacity: AppStrings.localized("events.filter_limited")
        }
    }

    func matches(_ event: CommunityEvent) -> Bool {
        switch self {
        case .all:
            true
        case .today:
            Calendar.current.isDateInToday(event.startsAt)
        case .thisWeek:
            Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.contains(event.startsAt) ?? false
        case .limitedCapacity:
            event.capacity != nil
        }
    }
}

private struct EventFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: EventFilter
    @Binding var sort: EventSort
    @Binding var selectedCountyCode: String?
    @Binding var selectedMunicipalityCode: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("events.filter_sorting")) {
                    Picker(AppStrings.localized("events.filter_sorting"), selection: $sort) {
                        ForEach(EventSort.allCases) { option in
                            Label(option.title, systemImage: option.symbol ?? "arrow.up.arrow.down")
                                .tag(option)
                        }
                    }
                }
                Section(AppStrings.localized("events.filter_date")) {
                    Picker(AppStrings.localized("events.filter_date"), selection: $selection) {
                        ForEach(EventFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                Section(AppStrings.localized("events.filter_location")) {
                    Picker(AppStrings.localized("events.filter_county"), selection: $selectedCountyCode) {
                        Text(AppStrings.localized("events.filter_all_counties")).tag(nil as String?)
                        ForEach(CommunityEventLocationCatalog.counties) { county in
                            Text(county.name).tag(county.code as String?)
                        }
                    }
                    Picker(AppStrings.localized("events.filter_municipality"), selection: $selectedMunicipalityCode) {
                        Text(AppStrings.localized("events.filter_all_municipalities")).tag(nil as String?)
                        ForEach(selectedMunicipalities) { municipality in
                            Text(municipality.name).tag(municipality.code as String?)
                        }
                    }
                    .disabled(selectedCountyCode == nil)
                }
            }
            .norgeScreen()
            .navigationTitle(AppStrings.localized("events.filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("groups.save")) { dismiss() }
                }
                .norgePlainToolbar()
            }
        }
        .onChange(of: selectedCountyCode) { _, _ in
            selectedMunicipalityCode = nil
        }
    }

    private var selectedMunicipalities: [CommunityEventMunicipality] {
        guard let selectedCountyCode,
            let county = CommunityEventLocationCatalog.counties.first(where: { $0.code == selectedCountyCode })
        else {
            return []
        }
        return county.municipalities
    }
}

private struct EventPaginationFooter: View {
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

private struct CommunityEventRow: View {
    let item: CommunityEventItem
    let isUpdating: Bool
    let isOwnEvent: Bool
    let onRSVP: (EventRSVPStatus?) async -> Void
    let onLike: (Bool) async -> Void
    let onRequestDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onInvite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.event.title).font(.headline)
                    Text(item.event.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await onLike(!item.isLiked) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.isLiked ? "heart.fill" : "heart")
                            .font(.title3)
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)").font(.caption2.monospacedDigit())
                        }
                    }
                    .foregroundStyle(item.isLiked ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel(
                    item.isLiked ? AppStrings.localized("events.unlike") : AppStrings.localized("events.like")
                )
                .accessibilityValue(String(format: AppStrings.localized("events.likes_count"), item.likeCount))
                Menu {
                    Button(AppStrings.localized("events.invite_people"), systemImage: "paperplane") {
                        onInvite()
                    }
                    if isOwnEvent {
                        Button(AppStrings.localized("events.delete"), role: .destructive, action: onRequestDelete)
                    } else {
                        Button(
                            AppStrings.localized("events.report"),
                            systemImage: "flag",
                            role: .destructive,
                            action: onReport
                        )
                        Button(
                            AppStrings.localized("feed.block"), systemImage: "hand.raised", role: .destructive,
                            action: onBlock)
                    }
                } label: {
                    NorgeOverflowMenuLabel()
                }
                .accessibilityLabel(AppStrings.localized("events.actions"))
            }
            if !item.media.isEmpty {
                CommunityEventMediaStrip(media: item.media)
            }
            NorgeMetadataLabel(title: item.event.areaLabel, systemImage: "mappin.and.ellipse", font: .subheadline)
            if let municipalityName = CommunityEventLocationCatalog.municipality(for: item.event.municipalityCode)?.name
            {
                NorgeMetadataLabel(title: municipalityName, systemImage: "building.2", font: .subheadline)
            }
            if let countyName = CommunityEventLocationCatalog.counties.first(where: { $0.code == item.event.countyCode }
            )?.name {
                NorgeMetadataLabel(title: countyName, systemImage: "map", font: .subheadline)
            }
            if let districtName = item.event.districtName, !districtName.isEmpty {
                NorgeMetadataLabel(title: districtName, systemImage: "mappin", font: .subheadline)
            }
            if let neighborhoodName = item.event.neighborhoodName, !neighborhoodName.isEmpty {
                NorgeMetadataLabel(title: neighborhoodName, systemImage: "signpost.right", font: .subheadline)
            }
            if let streetName = item.event.streetName, !streetName.isEmpty {
                NorgeMetadataLabel(title: streetName, systemImage: "road.lanes", font: .subheadline)
            }
            if let venueName = item.event.venueName {
                NorgeMetadataLabel(title: venueName, systemImage: "building.2", font: .subheadline)
            }
            NorgeMetadataLabel(
                title: item.event.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar",
                font: .subheadline)
            if let capacity = item.event.capacity {
                NorgeMetadataLabel(
                    title: String(format: AppStrings.localized("events.capacity"), capacity), systemImage: "person.2")
            }
            EventDetailBadges(event: item.event)
            HStack {
                NavigationLink {
                    CommunityMemberProfileView(
                        userID: item.event.hostID
                    )
                } label: {
                    Text(
                        String(
                            format: AppStrings.localized("events.hosted_by"),
                            item.host?.displayName ?? AppStrings.localized("feed.member"))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityHint(AppStrings.localized("member.profile_title"))
                Spacer()
                Menu {
                    Button(AppStrings.localized("events.interested")) { Task { await onRSVP(.interested) } }
                    Button(AppStrings.localized("events.going")) { Task { await onRSVP(.going) } }
                    if item.currentRSVP != nil {
                        Button(AppStrings.localized("events.cancel_rsvp"), role: .destructive) {
                            Task { await onRSVP(nil) }
                        }
                    }
                } label: {
                    Text(rsvpTitle).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isUpdating)
                .accessibilityLabel(AppStrings.localized("events.rsvp"))
            }
        }
        .padding(16)
        .background(
            Color.norgeInputSurface.opacity(0.62), in: RoundedRectangle(cornerRadius: NorgeCornerRadius.largeCard))
    }

    private var rsvpTitle: String {
        switch item.currentRSVP?.status {
        case .interested: AppStrings.localized("events.interested")
        case .going: AppStrings.localized("events.going")
        case nil: AppStrings.localized("events.rsvp")
        }
    }
}

private struct CommunityEventMediaStrip: View {
    let media: [CommunityEventMedia]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(media) { item in
                    if let url = item.signedURL {
                        CommunityCachedImage(url: url, variant: .full) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                        .frame(width: 180, height: 118)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(AppStrings.localized("events.photos"))
    }
}

private struct EventDetailBadges: View {
    let event: CommunityEvent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let category = event.category {
                    EventBadge(
                        title: AppStrings.localized("events.category.\(category)"), systemImage: "square.grid.2x2")
                }
                if let format = event.format {
                    EventBadge(title: AppStrings.localized("events.format.\(format)"), systemImage: "person.2")
                }
                if let ageRange = event.ageRange {
                    EventBadge(title: AppStrings.localized("events.age.\(ageRange)"), systemImage: "person.crop.circle")
                }
                if let alcoholPolicy = event.alcoholPolicy {
                    EventBadge(title: AppStrings.localized("events.alcohol.\(alcoholPolicy)"), systemImage: "wineglass")
                }
                if let priceType = event.priceType {
                    EventBadge(title: AppStrings.localized("events.price.\(priceType)"), systemImage: "ticket")
                }
                if event.isFamilyFriendly == true {
                    EventBadge(
                        title: AppStrings.localized("events.badge.family"),
                        systemImage: "figure.2.and.child.holdinghands")
                }
                if event.isAccessible == true {
                    EventBadge(title: AppStrings.localized("events.badge.accessible"), systemImage: "figure.roll")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct EventBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(Color.norgeInputSurface, in: Capsule())
    }
}

private struct CommunityEventInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    let eventID: UUID
    let eventTitle: String
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
            .navigationTitle(String(format: AppStrings.localized("events.invite_title"), eventTitle))
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
            try await eventsStore.invite(eventID: eventID, userID: profile.userID)
            sentIDs.insert(profile.userID)
        } catch {
            errorMessage = AppStrings.localized("invites.error")
        }
    }
}

private struct EventChoice: Identifiable, Hashable, Sendable {
    let value: String
    let key: String
    let symbol: String

    var id: String { value }
    var title: String { AppStrings.localized("events.\(key).\(value)") }
}

private enum EventChoiceCatalog {
    static let categories = [
        EventChoice(value: "social", key: "category", symbol: "person.3"),
        EventChoice(value: "sports", key: "category", symbol: "figure.run"),
        EventChoice(value: "workshop", key: "category", symbol: "hammer"),
        EventChoice(value: "culture", key: "category", symbol: "theatermasks"),
        EventChoice(value: "food", key: "category", symbol: "fork.knife"),
        EventChoice(value: "outdoors", key: "category", symbol: "mountain.2"),
        EventChoice(value: "networking", key: "category", symbol: "arrow.triangle.branch"),
        EventChoice(value: "family", key: "category", symbol: "figure.2.and.child.holdinghands"),
        EventChoice(value: "volunteering", key: "category", symbol: "hands.clap"),
        EventChoice(value: "market", key: "category", symbol: "bag"),
        EventChoice(value: "other", key: "category", symbol: "ellipsis.circle"),
    ]

    static let formats = [
        EventChoice(value: "in_person", key: "format", symbol: "mappin.and.ellipse"),
        EventChoice(value: "online", key: "format", symbol: "video"),
        EventChoice(value: "hybrid", key: "format", symbol: "rectangle.split.2x1"),
    ]

    static let ageRanges = [
        EventChoice(value: "all_ages", key: "age", symbol: "person.2"),
        EventChoice(value: "family", key: "age", symbol: "figure.2.and.child.holdinghands"),
        EventChoice(value: "18_plus", key: "age", symbol: "18.circle"),
        EventChoice(value: "20_plus", key: "age", symbol: "20.circle"),
        EventChoice(value: "custom", key: "age", symbol: "slider.horizontal.3"),
    ]

    static let alcoholPolicies = [
        EventChoice(value: "alcohol_free", key: "alcohol", symbol: "nosign"),
        EventChoice(value: "optional", key: "alcohol", symbol: "wineglass"),
        EventChoice(value: "served", key: "alcohol", symbol: "wineglass.fill"),
        EventChoice(value: "unknown", key: "alcohol", symbol: "questionmark.circle"),
    ]

    static let priceTypes = [
        EventChoice(value: "free", key: "price", symbol: "gift"),
        EventChoice(value: "paid", key: "price", symbol: "ticket"),
        EventChoice(value: "donation", key: "price", symbol: "heart"),
        EventChoice(value: "member_only", key: "price", symbol: "person.badge.key"),
    ]

    static let languages = [
        EventChoice(value: "english", key: "language", symbol: "character"),
        EventChoice(value: "norwegian", key: "language", symbol: "character.book.closed"),
        EventChoice(value: "turkish", key: "language", symbol: "character"),
        EventChoice(value: "multilingual", key: "language", symbol: "globe"),
        EventChoice(value: "other", key: "language", symbol: "ellipsis.circle"),
    ]
}

struct CreateCommunityEventView: View {  // swiftlint:disable:this type_body_length
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    let groupID: UUID?
    @State private var title = ""
    @State private var details = ""
    @State private var areaLabel = ""
    @State private var venueName = ""
    @State private var selectedCountyCode: String?
    @State private var selectedMunicipalityCode: String?
    @State private var districtName = ""
    @State private var neighborhoodName = ""
    @State private var streetName = ""
    @State private var category = "social"
    @State private var theme = ""
    @State private var eventFormat = "in_person"
    @State private var ageRange = "all_ages"
    @State private var alcoholPolicy = "alcohol_free"
    @State private var priceType = "free"
    @State private var language = "english"
    @State private var startsAt = Date.now.addingTimeInterval(86_400)
    @State private var hasCapacity = false
    @State private var capacity = 12
    @State private var isIndoor = true
    @State private var isFamilyFriendly = false
    @State private var isPetFriendly = false
    @State private var isAccessible = false
    @State private var foodProvided = false
    @State private var registrationRequired = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var preparedPhotos: [CommunityImageUpload] = []
    @State private var isLoadingPhotos = false
    @State private var photoTask: Task<Void, Never>?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var photoErrorMessage: String?

    init(groupID: UUID? = nil) {
        self.groupID = groupID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("events.section_basics")) {
                    TextField(AppStrings.localized("events.name"), text: $title)
                        .onChange(of: title) { _, value in
                            if value.count > 120 { title = String(value.prefix(120)) }
                        }
                    ZStack(alignment: .topLeading) {
                        if details.isEmpty {
                            Text(AppStrings.localized("events.details_placeholder"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $details)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel(AppStrings.localized("events.details"))
                            .onChange(of: details) { _, value in
                                if value.count > 4_000 { details = String(value.prefix(4_000)) }
                            }
                    }
                    .frame(minHeight: 120)
                }

                Section(AppStrings.localized("events.section_location")) {
                    Picker(AppStrings.localized("events.county"), selection: $selectedCountyCode) {
                        Text(AppStrings.localized("events.select_county")).tag(nil as String?)
                        ForEach(CommunityEventLocationCatalog.counties) { county in
                            Text(county.name).tag(county.code as String?)
                        }
                    }
                    Picker(AppStrings.localized("events.municipality"), selection: $selectedMunicipalityCode) {
                        Text(AppStrings.localized("events.select_municipality")).tag(nil as String?)
                        ForEach(selectedMunicipalities) { municipality in
                            Text(municipality.name).tag(municipality.code as String?)
                        }
                    }
                    .disabled(selectedCountyCode == nil)
                    TextField(AppStrings.localized("events.district"), text: $districtName)
                    TextField(AppStrings.localized("events.neighborhood"), text: $neighborhoodName)
                    TextField(AppStrings.localized("events.street_name"), text: $streetName)
                    TextField(AppStrings.localized("events.area"), text: $areaLabel)
                        .onChange(of: areaLabel) { _, value in
                            if value.count > 160 { areaLabel = String(value.prefix(160)) }
                        }
                    Text(AppStrings.localized("events.area_help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("events.venue_name_optional"), text: $venueName)
                    Text(AppStrings.localized("events.venue_name_help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(AppStrings.localized("events.section_schedule")) {
                    DatePicker(
                        AppStrings.localized("events.starts"), selection: $startsAt, in: Date.now...,
                        displayedComponents: [.date, .hourAndMinute])
                    Toggle(AppStrings.localized("events.limit_capacity"), isOn: $hasCapacity)
                    if hasCapacity {
                        Stepper(
                            String(format: AppStrings.localized("events.capacity"), capacity), value: $capacity,
                            in: 1...500)
                    }
                }

                Section(AppStrings.localized("events.section_details")) {
                    eventChoicePicker(
                        AppStrings.localized("events.category_title"), selection: $category,
                        choices: EventChoiceCatalog.categories)
                    TextField(AppStrings.localized("events.theme"), text: $theme)
                    eventChoicePicker(
                        AppStrings.localized("events.format_title"), selection: $eventFormat,
                        choices: EventChoiceCatalog.formats)
                    eventChoicePicker(
                        AppStrings.localized("events.age_title"), selection: $ageRange,
                        choices: EventChoiceCatalog.ageRanges)
                    eventChoicePicker(
                        AppStrings.localized("events.alcohol_title"), selection: $alcoholPolicy,
                        choices: EventChoiceCatalog.alcoholPolicies)
                    eventChoicePicker(
                        AppStrings.localized("events.price_title"), selection: $priceType,
                        choices: EventChoiceCatalog.priceTypes)
                    eventChoicePicker(
                        AppStrings.localized("events.language_title"), selection: $language,
                        choices: EventChoiceCatalog.languages)
                }

                Section(AppStrings.localized("events.section_access")) {
                    Toggle(AppStrings.localized("events.indoor"), isOn: $isIndoor)
                    Toggle(AppStrings.localized("events.family_friendly"), isOn: $isFamilyFriendly)
                    Toggle(AppStrings.localized("events.pet_friendly"), isOn: $isPetFriendly)
                    Toggle(AppStrings.localized("events.accessible"), isOn: $isAccessible)
                    Toggle(AppStrings.localized("events.food_provided"), isOn: $foodProvided)
                    Toggle(AppStrings.localized("events.registration_required"), isOn: $registrationRequired)
                }

                Section(AppStrings.localized("events.photos")) {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(1, 6 - preparedPhotos.count),
                        matching: .images
                    ) {
                        Label(AppStrings.localized("events.add_photos"), systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(isLoadingPhotos || preparedPhotos.count >= 6)

                    if isLoadingPhotos { ProgressView() }
                    if !preparedPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(preparedPhotos.enumerated()), id: \.offset) { index, photo in
                                    EventPhotoPreview(data: photo.data) {
                                        preparedPhotos.remove(at: index)
                                    }
                                }
                            }
                        }
                    }
                    Text(String(format: AppStrings.localized("events.photo_count"), preparedPhotos.count, 6))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let photoErrorMessage { NorgeInlineFeedback(message: photoErrorMessage) }
                }

                if let errorMessage { NorgeInlineFeedback(message: errorMessage) }
            }
            .norgeScreen()
            .navigationTitle(
                groupID == nil ? AppStrings.localized("events.create") : AppStrings.localized("events.create_group")
            )
            .navigationBarTitleDisplayMode(.inline)
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
                    .accessibilityLabel(AppStrings.localized("events.create"))
                    .disabled(!isValid || isCreating || isLoadingPhotos)
                }
                .norgePlainToolbar()
            }
            .onChange(of: selectedCountyCode) { _, _ in
                selectedMunicipalityCode = nil
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                photoTask?.cancel()
                let remaining = max(0, 6 - preparedPhotos.count)
                photoTask = Task { @MainActor in
                    isLoadingPhotos = true
                    photoErrorMessage = nil
                    defer {
                        isLoadingPhotos = false
                        selectedPhotos = []
                    }
                    do {
                        var uploads: [CommunityImageUpload] = []
                        for item in items.prefix(remaining) {
                            guard !Task.isCancelled, let data = try await item.loadTransferable(type: Data.self) else {
                                continue
                            }
                            uploads.append(try await CommunityImageProcessing.prepareJPEG(from: data))
                        }
                        guard !Task.isCancelled else { return }
                        preparedPhotos.append(contentsOf: uploads.prefix(remaining))
                    } catch {
                        photoErrorMessage = AppStrings.localized("media.processing_error")
                    }
                }
            }
            .onDisappear { photoTask?.cancel() }
        }
    }

    @ViewBuilder
    private func eventChoicePicker(
        _ title: String,
        selection: Binding<String>,
        choices: [EventChoice]
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices) { choice in
                Label(choice.title, systemImage: choice.symbol).tag(choice.value)
            }
        }
    }

    private var selectedMunicipalities: [CommunityEventMunicipality] {
        guard let selectedCountyCode,
            let county = CommunityEventLocationCatalog.counties.first(where: { $0.code == selectedCountyCode })
        else {
            return []
        }
        return county.municipalities
    }

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && details.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
            && selectedCountyCode != nil
            && selectedMunicipalityCode != nil
            && derivedAreaLabel.count >= 2
            && startsAt > Date.now.addingTimeInterval(15 * 60)
    }

    private var derivedAreaLabel: String {
        let explicitArea = areaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitArea.isEmpty { return explicitArea }
        if let neighborhood = neighborhoodName.nilIfBlank { return neighborhood }
        if let municipality = CommunityEventLocationCatalog.municipality(for: selectedMunicipalityCode) {
            return municipality.name
        }
        return ""
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            try await eventsStore.create(
                draft: CommunityEventDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: details.trimmingCharacters(in: .whitespacesAndNewlines),
                    areaLabel: derivedAreaLabel,
                    venueName: venueName.nilIfBlank,
                    countyCode: selectedCountyCode,
                    municipalityCode: selectedMunicipalityCode,
                    districtName: districtName.nilIfBlank,
                    neighborhoodName: neighborhoodName.nilIfBlank,
                    streetName: streetName.nilIfBlank,
                    category: category,
                    theme: theme.nilIfBlank,
                    format: eventFormat,
                    ageRange: ageRange,
                    alcoholPolicy: alcoholPolicy,
                    priceType: priceType,
                    language: language,
                    isIndoor: isIndoor,
                    isFamilyFriendly: isFamilyFriendly,
                    isPetFriendly: isPetFriendly,
                    isAccessible: isAccessible,
                    foodProvided: foodProvided,
                    registrationRequired: registrationRequired,
                    startsAt: startsAt,
                    capacity: hasCapacity ? capacity : nil,
                    groupID: groupID,
                    photos: preparedPhotos
                ))
            dismiss()
        } catch {
            errorMessage = AppStrings.localized("events.create_error")
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct EventPhotoPreview: View {
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 84)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.72))
                    .font(.title3)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("media.remove_photo"))
        }
    }
}
