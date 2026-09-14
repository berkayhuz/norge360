import PhotosUI
import SwiftUI
// Conversation list and detail share request, blocking and read-state flows.
// swiftlint:disable file_length
import UIKit

struct CommunityConversationsView: View {  // swiftlint:disable:this type_body_length
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    @State private var query = ""
    @State private var actionError: String?
    @State private var respondingID: UUID?
    @State private var deleteConversationTarget: CommunityConversationSummary?
    @FocusState private var isSearchFocused: Bool
    @State private var inboxMode: InboxMode = .direct

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NorgeTopBar {
                    HStack(spacing: 8) {
                        NorgeTopBarSearchField(
                            text: $query,
                            prompt: AppStrings.localized(
                                inboxMode == .direct ? "chat.search_conversations" : "chat.search_group_chats"
                            ),
                            focus: $isSearchFocused
                        )
                        Button {
                            inboxMode = inboxMode == .direct ? .groups : .direct
                            query = ""
                        } label: {
                            NorgeTopBarActionLabel(systemName: inboxMode == .direct ? "person.3" : "message")
                        }
                        .accessibilityLabel(
                            AppStrings.localized(
                                inboxMode == .direct ? "chat.open_group_chats" : "chat.open_direct_chats"))
                    }
                }
                if inboxMode == .direct {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: 0).id("messages-top")
                                ScrollHeaderVisibilityObserver { visible in
                                    tabRouter.setTabBarCompact(!visible, for: .messages)
                                }
                                .frame(height: 0)
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    if let error = actionError ?? conversationsStore.errorMessage {
                                        NorgeInlineFeedback(message: error).padding()
                                    }
                                    if conversationsStore.isLoading && conversationsStore.conversations.isEmpty {
                                        NorgeLoadingState(topPadding: 60)
                                    } else if matchingConversations.isEmpty {
                                        NorgeUnavailableState(
                                            AppStrings.localized(
                                                query.isEmpty ? "messages.empty_title" : "chat.no_results"),
                                            systemImage: query.isEmpty
                                                ? "bubble.left.and.bubble.right" : "magnifyingglass",
                                            description: AppStrings.localized(
                                                query.isEmpty ? "messages.empty_body" : "chat.try_another_search")
                                        ).padding(.top, 30)
                                    }
                                    if !incomingRequests.isEmpty {
                                        sectionTitle("messages.requests")
                                        ForEach(incomingRequests) { conversation in
                                            MessageRequestRow(
                                                conversation: conversation,
                                                isResponding: respondingID == conversation.id
                                            ) { accept in
                                                Task { await respond(to: conversation, accept: accept) }
                                            }.padding(.horizontal, 16).padding(.vertical, 10)
                                        }
                                    }
                                    conversationLinks(activeConversations)
                                    if !restrictedConversations.isEmpty {
                                        sectionTitle("chat.restricted")
                                        conversationLinks(restrictedConversations)
                                    }
                                    if !outgoingRequests.isEmpty {
                                        sectionTitle("messages.pending")
                                        ForEach(outgoingRequests) { conversation in
                                            ConversationRow(
                                                conversation: conversation,
                                                subtitle: AppStrings.localized("messages.request_sent")
                                            )
                                            .padding(.horizontal, 16).padding(.vertical, 13)
                                        }
                                    }
                                    if conversationsStore.hasMoreConversations {
                                        NorgeSkeleton(width: 180, height: 14)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 18)
                                            .task { await conversationsStore.loadMore() }
                                    }
                                }
                                .padding(.bottom, 6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .contentMargins(.top, 0, for: .scrollContent)
                        .refreshable { await conversationsStore.reload() }
                        .onChange(of: tabRouter.messagesScrollToTopToken) { _, _ in
                            withAnimation(.easeOut(duration: 0.24)) {
                                proxy.scrollTo("messages-top", anchor: .top)
                            }
                        }
                    }
                } else {
                    groupChats
                }
            }
            .background(Color.norgeAppBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await conversationsStore.activate()
                await groupsStore.activate()
            }
            .confirmationDialog(
                AppStrings.localized("chat.delete_conversation"),
                isPresented: Binding(
                    get: { deleteConversationTarget != nil },
                    set: { if !$0 { deleteConversationTarget = nil } }
                ),
                presenting: deleteConversationTarget
            ) { conversation in
                Button(AppStrings.localized("chat.delete_conversation"), role: .destructive) {
                    Task { await updateConversation(conversation) { $0.isHidden = true } }
                }
                Button(AppStrings.localized("feed.cancel"), role: .cancel) { deleteConversationTarget = nil }
            } message: { _ in
                Text(AppStrings.localized("chat.delete_conversation_confirm"))
            }
        }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(AppStrings.localized(key)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
    }

    private var groupChats: some View {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = groupsStore.groups.filter {
            groupsStore.joinedGroupIDs.contains($0.id)
                && (normalizedQuery.isEmpty
                    || $0.name.localizedStandardContains(normalizedQuery)
                    || $0.description.localizedStandardContains(normalizedQuery)
                    || $0.slug.localizedStandardContains(normalizedQuery))
        }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("group-chats-top")
                    ScrollHeaderVisibilityObserver { visible in
                        tabRouter.setTabBarCompact(!visible, for: .messages)
                    }
                    .frame(height: 0)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if groups.isEmpty {
                            NorgeUnavailableState(
                                AppStrings.localized(
                                    normalizedQuery.isEmpty ? "chat.group_chats_empty_title" : "chat.no_results"
                                ),
                                systemImage: normalizedQuery.isEmpty ? "person.3" : "magnifyingglass",
                                description: AppStrings.localized(
                                    normalizedQuery.isEmpty ? "chat.group_chats_empty_body" : "chat.try_another_search"
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 44)
                        } else {
                            ForEach(groups) { group in
                                NavigationLink {
                                    CommunityGroupChatView(group: group)
                                } label: {
                                    HStack(spacing: 13) {
                                        CommunityGroupImageView(
                                            photoURL: group.photoURL,
                                            isCityGroup: group.cityOrRegion != nil,
                                            width: 56,
                                            height: 56
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(group.name).font(.body.weight(.semibold))
                                            Text(group.description).font(.subheadline).foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                            .foregroundStyle(
                                                .secondary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .onChange(of: tabRouter.messagesScrollToTopToken) { _, _ in
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo("group-chats-top", anchor: .top)
                }
            }
            .refreshable { await groupsStore.reload() }
        }
    }

    private func conversationLinks(_ conversations: [CommunityConversationSummary]) -> some View {
        ForEach(conversations) { conversation in
            NavigationLink {
                CommunityConversationDetailView(conversation: conversation)
            } label: {
                ConversationRow(
                    conversation: conversation,
                    isMuted: conversationsStore.settings(for: conversation.id).isMuted,
                    isPinned: conversationsStore.settings(for: conversation.id).isPinned
                )
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.primary)
            .transaction { transaction in transaction.animation = nil }
            .contextMenu {
                let settings = conversationsStore.settings(for: conversation.id)
                Button(
                    AppStrings.localized(settings.isPinned ? "chat.unpin" : "chat.pin"),
                    systemImage: settings.isPinned ? "pin.slash" : "pin"
                ) {
                    Task { await updateConversation(conversation) { $0.isPinned.toggle() } }
                }
                Button(
                    AppStrings.localized(settings.isMuted ? "chat.unmute" : "chat.mute"),
                    systemImage: settings.isMuted ? "bell" : "bell.slash"
                ) {
                    Task { await updateConversation(conversation) { $0.isMuted.toggle() } }
                }
                Button(AppStrings.localized("chat.delete_conversation"), systemImage: "trash", role: .destructive) {
                    deleteConversationTarget = conversation
                }
            }
        }
    }

    private var matchingConversations: [CommunityConversationSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversationsStore.conversations.filter {
            $0.status != .declined
                && (normalized.isEmpty || $0.displayName.localizedStandardContains(normalized)
                    || $0.username.localizedStandardContains(normalized))
        }
    }
    private var activeConversations: [CommunityConversationSummary] {
        matchingConversations
            .filter { $0.status == .active && !conversationsStore.settings(for: $0.id).isRestricted }
            .sorted { lhs, rhs in
                let lhsPinned = conversationsStore.settings(for: lhs.id).isPinned
                let rhsPinned = conversationsStore.settings(for: rhs.id).isPinned
                return lhsPinned == rhsPinned ? lhs.updatedAt > rhs.updatedAt : lhsPinned
            }
    }
    private var restrictedConversations: [CommunityConversationSummary] {
        matchingConversations.filter { $0.status == .active && conversationsStore.settings(for: $0.id).isRestricted }
    }
    private var incomingRequests: [CommunityConversationSummary] {
        matchingConversations.filter { $0.status == .pending && $0.requestedByID != authenticationStore.user?.id }
    }
    private var outgoingRequests: [CommunityConversationSummary] {
        matchingConversations.filter { $0.status == .pending && $0.requestedByID == authenticationStore.user?.id }
    }
    private func respond(to conversation: CommunityConversationSummary, accept: Bool) async {
        respondingID = conversation.id
        defer { respondingID = nil }
        do { try await conversationsStore.respond(conversationID: conversation.id, accept: accept) } catch {
            actionError = AppStrings.localized("messages.error")
        }
    }

    private func updateConversation(
        _ conversation: CommunityConversationSummary,
        change: (inout CommunityConversationSettings) -> Void
    ) async {
        var settings = conversationsStore.settings(for: conversation.id)
        change(&settings)
        do {
            try await conversationsStore.updateSettings(settings)
            deleteConversationTarget = nil
            actionError = nil
        } catch {
            actionError = AppStrings.localized("messages.error")
        }
    }
}

private enum InboxMode { case direct, groups }

private struct ConversationRow: View {
    let conversation: CommunityConversationSummary
    var subtitle: String?
    var isMuted = false
    var isPinned = false

    var body: some View {
        HStack(spacing: 13) {
            CommunityAvatarView(url: conversation.avatarURL, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(conversation.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    if isMuted {
                        Image(systemName: "bell.slash").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel(AppStrings.localized("chat.muted"))
                    }
                    if isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel(AppStrings.localized("chat.pinned"))
                    }
                }
                Text(subtitle ?? conversation.lastMessage ?? "@\(conversation.username)")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(conversation.updatedAt, format: .relative(presentation: .named))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct MessageRequestRow: View {
    let conversation: CommunityConversationSummary
    let isResponding: Bool
    let respond: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CommunityMemberProfileView(userID: conversation.otherUserID)
            } label: {
                ConversationRow(conversation: conversation, subtitle: AppStrings.localized("messages.request_body"))
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                Button(AppStrings.localized("messages.decline"), role: .destructive) { respond(false) }
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                Button(AppStrings.localized("messages.accept")) { respond(true) }
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
            }.disabled(isResponding)
        }
    }
}

struct CommunityConversationDetailView: View {  // swiftlint:disable:this type_body_length
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    let conversation: CommunityConversationSummary
    @State private var messages: [CommunityMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var reportTarget: CommunityMessage?
    @State private var hideTarget: CommunityMessage?
    @State private var readReceipt: CommunityMessageReadReceipt?
    @State private var errorMessage: String?
    @State private var showsSettings = false
    @State private var showsSearch = false
    @State private var messageQuery = ""
    @State private var debouncedMessageQuery = ""
    @State private var customBackgroundData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pendingAttachmentID: UUID?
    @State private var pendingImage: UIImage?
    @State private var isPendingImageScan = false
    @State private var isPreparingImage = false
    @State private var showsCamera = false
    @State private var hasLoadedDraft = false
    @State private var draftSessionID: UUID?
    @State private var hasMoreOlderMessages = false
    @State private var isLoadingOlderMessages = false
    @StateObject private var realtimeDebouncer = NorgeTaskDebouncer()

    private var settings: CommunityConversationSettings { conversationsStore.settings(for: conversation.id) }
    private var visibleMessages: [CommunityMessage] {
        debouncedMessageQuery.isEmpty
            ? messages : messages.filter { $0.body.localizedStandardContains(debouncedMessageQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSearch {
                HStack(spacing: 8) {
                    NorgeTopBarSearchField(text: $messageQuery, prompt: AppStrings.localized("chat.search_messages"))
                    Button {
                        showsSearch = false
                        messageQuery = ""
                    } label: {
                        NorgeTopBarActionLabel(systemName: "xmark")
                    }.accessibilityLabel(AppStrings.localized("chat.close_search"))
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            if let errorMessage {
                NorgeInlineFeedback(message: errorMessage)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
            }
            if isLoading && messages.isEmpty {
                NorgeSkeletonList(rowCount: 3, showsMedia: false)
                    .padding(.horizontal, 16)
            } else {
                messageList
            }
        }
        .background {
            CommunityChatBackdrop(style: settings.backgroundStyle, customImageData: customBackgroundData)
                .ignoresSafeArea()
        }
        .background(Color.norgeAppBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.norgeAppBackground, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    CommunityMemberProfileView(userID: conversation.otherUserID)
                } label: {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                }.buttonStyle(.plain)
                    .accessibilityHint(AppStrings.localized("chat.open_profile"))
            }.norgePlainToolbar()
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(AppStrings.localized("chat.settings"))
            }.norgePlainToolbar()
        }
        .sheet(
            isPresented: $showsSettings,
            onDismiss: {
                guard let userID = authenticationStore.user?.id else {
                    customBackgroundData = nil
                    return
                }
                Task {
                    customBackgroundData = await CommunityChatBackgroundImageStore.shared.imageData(
                        for: conversation.id, userID: userID
                    )
                }
            },
            content: {
                CommunityConversationSettingsView(conversation: conversation) {
                    showsSettings = false
                    showsSearch = true
                } onBlocked: {
                    messages = []
                    showsSettings = false
                    dismiss()
                }
            }
        )
        .sheet(isPresented: $showsCamera) {
            CameraImagePicker { data in
                Task { await stageImage(data) }
            }
        }
        .task {
            guard let userID = authenticationStore.user?.id else { return }
            draftSessionID = await CommunityMessageDraftStore.shared.beginSession(ownerID: userID)
            customBackgroundData = await CommunityChatBackgroundImageStore.shared.imageData(
                for: conversation.id, userID: userID
            )
            if let ownerID = authenticationStore.user?.id {
                draft =
                    await CommunityMessageDraftStore.shared.load(
                        conversationID: conversation.id, ownerID: ownerID
                    ) ?? ""
                await restorePendingImage(ownerID: ownerID)
            }
            hasLoadedDraft = true
            await reload()
        }
        .task(id: draft) {
            guard hasLoadedDraft, let ownerID = authenticationStore.user?.id,
                let draftSessionID
            else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await CommunityMessageDraftStore.shared.save(
                    draft, conversationID: conversation.id, ownerID: ownerID, sessionID: draftSessionID
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .task {
            let events = await conversationsStore.messageEvents(conversationID: conversation.id)
            for await _ in events {
                guard !Task.isCancelled else { return }
                realtimeDebouncer.schedule(after: .milliseconds(200)) {
                    await refreshFromRealtime()
                }
            }
        }
        .task(id: pendingAttachmentID) { await pollPendingImageScan() }
        .onDisappear { realtimeDebouncer.cancel() }
        .task(id: messageQuery) {
            do {
                try await Task.sleep(for: .milliseconds(220))
                debouncedMessageQuery = messageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {}
        }
        .confirmationDialog(
            AppStrings.localized("messages.report_title"),
            isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } })
        ) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                    guard let reportTarget else { return }
                    Task { await report(reportTarget, reason: reason) }
                }
            }
        }
        .confirmationDialog(
            AppStrings.localized("messages.delete_for_me"),
            isPresented: Binding(get: { hideTarget != nil }, set: { if !$0 { hideTarget = nil } })
        ) {
            Button(AppStrings.localized("messages.delete_for_me"), role: .destructive) {
                guard let hideTarget else { return }
                Task { await hide(hideTarget) }
            }
        } message: {
            Text(AppStrings.localized("messages.delete_for_me_confirm"))
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollHeaderVisibilityObserver { visible in
                        tabRouter.setTabBarCompact(!visible, for: .messages)
                    }
                    .frame(height: 0)
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if hasMoreOlderMessages {
                            Group {
                                if isLoadingOlderMessages {
                                    NorgeSkeleton(width: 180, height: 34, cornerRadius: 17)
                                } else {
                                    Color.clear.frame(height: 1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                guard !isLoadingOlderMessages else { return }
                                Task {
                                    let anchorID = await loadOlderMessages()
                                    if let anchorID { proxy.scrollTo(anchorID, anchor: .top) }
                                }
                            }
                        }
                        if visibleMessages.isEmpty {
                            NorgeUnavailableState(
                                AppStrings.localized(
                                    debouncedMessageQuery.isEmpty ? "chat.start_conversation" : "chat.no_results"),
                                systemImage: debouncedMessageQuery.isEmpty
                                    ? "bubble.left.and.bubble.right" : "magnifyingglass"
                            ).frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        ForEach(visibleMessages) { message in
                            CommunityMessageBubble(
                                message: message, isMine: message.senderID == authenticationStore.user?.id,
                                showsReadReceipt: shouldShowReadReceipt(for: message), bubbleColor: settings.bubbleColor
                            ) {
                                reportTarget = message
                            } hide: {
                                hideTarget = message
                            }
                            .id(message.id)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refreshFromPull() }
            .onChange(of: messages.last?.id) { _, id in
                if let id, !showsSearch { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if settings.isRestricted {
                Text(AppStrings.localized("chat.restricted_composer"))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            if let pendingImage {
                HStack(spacing: 10) {
                    Image(uiImage: pendingImage).resizable().scaledToFill()
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(
                        AppStrings.localized(
                            isPendingImageScan ? "groups.chat_image_checking" : "groups.chat_image_ready"
                        )
                    ).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        guard let attachmentID = pendingAttachmentID else { return }
                        pendingAttachmentID = nil
                        self.pendingImage = nil
                        isPendingImageScan = false
                        Task {
                            await discardImage(attachmentID)
                            if let ownerID = authenticationStore.user?.id {
                                await CommunityPendingImageStore.shared.remove(
                                    ownerID: ownerID, scopeID: conversation.id, kind: .direct
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(AppStrings.localized("groups.chat_remove_image"))
                }.padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 10) {
                let preparingImage = isPreparingImage
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    if preparingImage {
                        ProgressView().frame(width: 28, height: 46)
                    } else {
                        Image(systemName: "photo").font(.title3).frame(width: 28, height: 46)
                    }
                }
                .disabled(isSending || isPreparingImage || settings.isRestricted)
                .accessibilityLabel(AppStrings.localized("groups.chat_add_photo"))
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showsCamera = true
                    } label: {
                        Image(systemName: "camera").font(.title3).frame(width: 28, height: 46)
                    }
                    .disabled(isSending || isPreparingImage || settings.isRestricted)
                    .accessibilityLabel(AppStrings.localized("groups.chat_add_photo"))
                }
                TextField(AppStrings.localized("messages.placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .norgeComposerInput()
                    .onChange(of: draft) { _, value in
                        let normalized = CommunityMessageDraft.removingLeadingWhitespace(value)
                        if normalized != value { draft = normalized }
                    }
                NorgeCircularSendButton(
                    isSending: isSending,
                    isEnabled: !isSending && !isPreparingImage && !isPendingImageScan && !settings.isRestricted
                        && (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            || pendingAttachmentID != nil),
                    accessibilityLabel: AppStrings.localized("chat.send")
                ) { Task { await send() } }
            }.padding(.horizontal, 16)
                .disabled(settings.isRestricted)
        }
        .padding(.top, 10).padding(.bottom, 8).background(Color.norgeAppBackground)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await prepareImage(item) }
        }
    }

    private func reload(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }
        do {
            let page = try await conversationsStore.messagePage(conversationID: conversation.id, before: nil)
            messages = page.items
            hasMoreOlderMessages = page.hasMoreOlder
            if !settings.isRestricted { await conversationsStore.markRead(conversationID: conversation.id) }
            // Receipt state is optional privacy data. Its endpoint must not
            // turn an otherwise successful message refresh into an error.
            readReceipt = try? await conversationsStore.readReceipt(conversationID: conversation.id)
            errorMessage = nil
        } catch { errorMessage = AppStrings.localized("messages.error") }
    }

    private func refreshFromRealtime() async {
        guard let lastMessage = messages.last else {
            await reload(showSpinner: false)
            return
        }
        do {
            let delta = try await conversationsStore.messages(
                conversationID: conversation.id,
                after: CommunityMessageCursor(createdAt: lastMessage.createdAt, id: lastMessage.id)
            )
            let knownIDs = Set(messages.map(\.id))
            let newMessages = delta.filter { !knownIDs.contains($0.id) }
            guard !newMessages.isEmpty else { return }
            messages.append(contentsOf: newMessages)
            if !settings.isRestricted,
                let viewerID = authenticationStore.user?.id,
                newMessages.contains(where: { $0.senderID != viewerID })
            {
                await conversationsStore.markRead(conversationID: conversation.id)
            }
        } catch {
            errorMessage = AppStrings.localized("messages.error")
        }
    }

    private func loadOlderMessages() async -> UUID? {
        guard !isLoadingOlderMessages, hasMoreOlderMessages, let oldest = messages.first else { return nil }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        do {
            let page = try await conversationsStore.messagePage(
                conversationID: conversation.id,
                before: CommunityMessageCursor(createdAt: oldest.createdAt, id: oldest.id)
            )
            let knownIDs = Set(messages.map(\.id))
            let olderMessages = page.items.filter { !knownIDs.contains($0.id) }
            messages.insert(contentsOf: olderMessages, at: 0)
            hasMoreOlderMessages = page.hasMoreOlder
            return oldest.id
        } catch {
            errorMessage = AppStrings.localized("messages.error")
            return nil
        }
    }

    private func refreshFromPull() async {
        // Messages are delivered through the live stream. If this detail has
        // already loaded its complete server result, retain the native spinner
        // but do not issue a duplicate request just because it was pulled.
        guard messages.isEmpty else { return }
        await reload(showSpinner: false)
    }
    private func send() async {
        guard !isSending, !isPendingImageScan, !settings.isRestricted else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || pendingAttachmentID != nil else { return }
        isSending = true
        defer { isSending = false }
        do {
            if let pendingAttachmentID {
                try await conversationsStore.send(
                    conversationID: conversation.id, body: body, attachmentID: pendingAttachmentID)
            } else {
                try await conversationsStore.send(conversationID: conversation.id, body: body)
            }
            draft = ""
            if let ownerID = authenticationStore.user?.id {
                await CommunityMessageDraftStore.shared.remove(
                    conversationID: conversation.id, ownerID: ownerID
                )
            }
            pendingAttachmentID = nil
            pendingImage = nil
            isPendingImageScan = false
            if let ownerID = authenticationStore.user?.id {
                await CommunityPendingImageStore.shared.remove(
                    ownerID: ownerID, scopeID: conversation.id, kind: .direct
                )
            }
            await refreshFromRealtime()
        } catch { errorMessage = AppStrings.localized("messages.error") }
    }
    private func prepareImage(_ item: PhotosPickerItem) async {
        isPreparingImage = true
        defer {
            isPreparingImage = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CommunityMediaError.unsupportedImage
            }
            await stageImage(data, managesLoadingState: false)
        } catch {
            errorMessage = AppStrings.localized("groups.chat_image_error")
        }
    }
    private func stageImage(_ data: Data, managesLoadingState: Bool = true) async {
        guard !isPreparingImage || !managesLoadingState else { return }
        if managesLoadingState { isPreparingImage = true }
        defer { if managesLoadingState { isPreparingImage = false } }
        do {
            let upload = try await CommunityImageProcessing.prepareJPEG(from: data)
            guard
                let image = CommunityImageDecoding.image(
                    from: upload.data, variant: .thumbnail(maxPixelDimension: 256)
                )
            else {
                throw CommunityMediaError.unsupportedImage
            }
            do {
                let attachmentID = try await conversationsStore.stageImage(
                    conversationID: conversation.id, jpegData: upload.data
                )
                pendingAttachmentID = attachmentID
                pendingImage = image
                isPendingImageScan = false
            } catch let error as CommunityDirectChatMediaError {
                switch error {
                case .pendingScan(let attachmentID):
                    pendingAttachmentID = attachmentID
                    pendingImage = image
                    isPendingImageScan = true
                    if let ownerID = authenticationStore.user?.id {
                        await CommunityPendingImageStore.shared.save(
                            attachmentID: attachmentID,
                            ownerID: ownerID,
                            scopeID: conversation.id,
                            kind: .direct,
                            jpegData: upload.data
                        )
                    }
                case .rejected:
                    errorMessage = AppStrings.localized("groups.chat_image_rejected")
                case .needsReview, .unavailable:
                    errorMessage = AppStrings.localized("groups.chat_image_error")
                }
            }
        } catch {
            errorMessage = AppStrings.localized("groups.chat_image_error")
        }
    }

    private func restorePendingImage(ownerID: UUID) async {
        guard
            let pending = await CommunityPendingImageStore.shared.load(
                ownerID: ownerID, scopeID: conversation.id, kind: .direct
            ),
            let image = CommunityImageDecoding.image(
                from: pending.jpegData, variant: .thumbnail(maxPixelDimension: 256)
            )
        else { return }
        pendingAttachmentID = pending.attachmentID
        pendingImage = image
        isPendingImageScan = true
    }

    private func pollPendingImageScan() async {
        guard isPendingImageScan, let attachmentID = pendingAttachmentID else { return }
        let delays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30), .seconds(30)]
        for delay in delays {
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled, pendingAttachmentID == attachmentID else { return }
                let outcome = try await conversationsStore.scanStatus(attachmentID: attachmentID)
                switch outcome {
                case .passed:
                    isPendingImageScan = false
                    return
                case .pendingScan:
                    continue
                case .rejected:
                    await clearPendingImage(attachmentID: attachmentID)
                    errorMessage = AppStrings.localized("groups.chat_image_rejected")
                    return
                case .needsReview:
                    await clearPendingImage(attachmentID: attachmentID)
                    errorMessage = AppStrings.localized("groups.chat_image_review")
                    return
                case .unavailable:
                    await clearPendingImage(attachmentID: attachmentID)
                    errorMessage = AppStrings.localized("groups.chat_image_error")
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
        errorMessage = AppStrings.localized("groups.chat_image_error")
    }

    private func clearPendingImage(attachmentID: UUID) async {
        pendingAttachmentID = nil
        pendingImage = nil
        isPendingImageScan = false
        await discardImage(attachmentID)
        if let ownerID = authenticationStore.user?.id {
            await CommunityPendingImageStore.shared.remove(
                ownerID: ownerID, scopeID: conversation.id, kind: .direct
            )
        }
    }
    private func discardImage(_ attachmentID: UUID) async {
        do {
            try await conversationsStore.cancelImage(attachmentID: attachmentID)
        } catch {
            // The preview is gone locally. A server-side cleanup pass handles a
            // transient cancellation failure without exposing an orphaned URL.
        }
    }
    private func hide(_ message: CommunityMessage) async {
        do {
            try await conversationsStore.hide(messageID: message.id)
            hideTarget = nil
            await reload(showSpinner: false)
        } catch { errorMessage = AppStrings.localized("messages.error") }
    }
    private func report(_ message: CommunityMessage, reason: CommunityReportReason) async {
        do {
            try await conversationsStore.report(messageID: message.id, reason: reason)
            reportTarget = nil
        } catch { errorMessage = AppStrings.localized("messages.error") }
    }
    private func shouldShowReadReceipt(for message: CommunityMessage) -> Bool {
        guard !settings.isRestricted, message.senderID == authenticationStore.user?.id,
            message.id == messages.last(where: { $0.senderID == authenticationStore.user?.id })?.id,
            readReceipt?.areReadReceiptsEnabled == true,
            let otherLastReadAt = readReceipt?.otherLastReadAt
        else { return false }
        return otherLastReadAt >= message.createdAt
    }
}
