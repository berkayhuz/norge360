import SwiftUI

// Event list, RSVP and event creation form one complete community slice.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct CommunityEventsView: View {
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    let group: CommunityGroup?
    let canCreateGroupEvent: Bool
    let showsLikedOnly: Bool
    let usesEmbeddedChrome: Bool
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

    init(
        group: CommunityGroup? = nil,
        canCreateGroupEvent: Bool = true,
        showsLikedOnly: Bool = false,
        usesEmbeddedChrome: Bool = false,
        focusedEventID: UUID? = nil
    ) {
        self.group = group
        self.canCreateGroupEvent = canCreateGroupEvent
        self.showsLikedOnly = showsLikedOnly
        self.usesEmbeddedChrome = usesEmbeddedChrome
        self.focusedEventID = focusedEventID
    }

    var body: some View {
        Group {
            if eventsStore.isLoading && eventsStore.items.isEmpty {
                NorgeLoadingState(fillsAvailableSpace: true)
            } else {
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
                    }
                    .listRowBackground(Color.norgeAppBackground)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: NorgeSpacing.medium, bottom: 4, trailing: NorgeSpacing.medium))
                    if group == nil && !showsLikedOnly {
                        Section {
                            EventSortPicker(selection: $sort)
                        }
                        .listRowBackground(Color.norgeAppBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            EdgeInsets(top: 4, leading: NorgeSpacing.medium, bottom: 8, trailing: NorgeSpacing.medium))
                    }
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
            }
        }
        .norgeScreen()
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
            EventFiltersView(selection: $eventFilter)
                .presentationDetents([.medium])
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
                ].contains {
                    $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            return matchesQuery && eventFilter.matches(item.event)
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
    var title: String { AppStrings.localized("events.sort.\(rawValue)") }
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

    var body: some View {
        NavigationStack {
            Form {
                Picker(AppStrings.localized("events.filter_date"), selection: $selection) {
                    ForEach(EventFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
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
    }
}

private struct EventPaginationFooter: View {
    let isLoading: Bool

    var body: some View {
        HStack {
            Spacer()
            if isLoading { ProgressView() }
            Spacer()
        }
        .frame(height: 44)
        .listRowBackground(Color.norgeAppBackground)
        .listRowSeparator(.hidden)
    }
}

private struct EventSortPicker: View {
    @Binding var selection: EventSort

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EventSort.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        Label(option.title, systemImage: option.symbol ?? "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == option ? Color.primary : Color.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .background(
                                selection == option ? Color.primary.opacity(0.10) : Color.norgeInputSurface,
                                in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }
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
                        Text("\(item.likeCount)").font(.caption2.monospacedDigit())
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
                        Button(AppStrings.localized("events.report"), role: .destructive, action: onReport)
                        Button(
                            AppStrings.localized("feed.block"), systemImage: "hand.raised", role: .destructive,
                            action: onBlock)
                    }
                } label: {
                    NorgeOverflowMenuLabel()
                }
                .accessibilityLabel(AppStrings.localized("events.actions"))
            }
            NorgeMetadataLabel(title: item.event.areaLabel, systemImage: "mappin.and.ellipse", font: .subheadline)
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

struct CreateCommunityEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventsStore: CommunityEventsStore
    let groupID: UUID?
    @State private var title = ""
    @State private var details = ""
    @State private var areaLabel = ""
    @State private var venueName = ""
    @State private var startsAt = Date.now.addingTimeInterval(86_400)
    @State private var hasCapacity = false
    @State private var capacity = 12
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(groupID: UUID? = nil) {
        self.groupID = groupID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppStrings.localized("events.name"), text: $title)
                        .onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
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
                    TextField(AppStrings.localized("events.area"), text: $areaLabel)
                        .onChange(of: areaLabel) { _, value in
                            if value.count > 160 { areaLabel = String(value.prefix(160)) }
                        }
                    Text(AppStrings.localized("events.area_help")).font(.footnote).foregroundStyle(.secondary)
                    TextField(AppStrings.localized("events.venue_name_optional"), text: $venueName)
                        .onChange(of: venueName) { _, value in
                            if value.count > 120 { venueName = String(value.prefix(120)) }
                        }
                    Text(AppStrings.localized("events.venue_name_help"))
                        .font(.footnote).foregroundStyle(.secondary)
                    DatePicker(
                        AppStrings.localized("events.starts"), selection: $startsAt, in: Date.now...,
                        displayedComponents: [.date, .hourAndMinute])
                    Toggle(AppStrings.localized("events.limit_capacity"), isOn: $hasCapacity)
                    if hasCapacity {
                        Stepper(
                            String(format: AppStrings.localized("events.capacity"), capacity), value: $capacity,
                            in: 1...500)
                    }
                    if let errorMessage { NorgeInlineFeedback(message: errorMessage) }
                }
                .listRowBackground(Color.norgeAppBackground)
            }
            .norgeScreen()
            .navigationTitle(
                groupID == nil ? AppStrings.localized("events.create") : AppStrings.localized("events.create_group")
            )
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
                    .accessibilityLabel(AppStrings.localized("events.create"))
                    .disabled(!isValid || isCreating)
                }
                .norgePlainToolbar()
            }
        }
    }

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && details.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
            && areaLabel.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && startsAt > Date.now.addingTimeInterval(15 * 60)
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            try await eventsStore.create(
                draft: CommunityEventDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: details.trimmingCharacters(in: .whitespacesAndNewlines),
                    areaLabel: areaLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                    venueName: venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : venueName.trimmingCharacters(in: .whitespacesAndNewlines),
                    startsAt: startsAt,
                    capacity: hasCapacity ? capacity : nil,
                    groupID: groupID
                ))
            dismiss()
        } catch {
            errorMessage = AppStrings.localized("events.create_error")
        }
    }
}
