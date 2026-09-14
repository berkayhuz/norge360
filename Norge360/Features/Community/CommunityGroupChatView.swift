import PhotosUI
import SwiftUI
// The group-chat screen keeps moderation, message loading and composer state
// together because they share the same server-authorized lifecycle.
// swiftlint:disable file_length
import UIKit

struct CommunityGroupChatView: View {  // swiftlint:disable:this type_body_length
    @EnvironmentObject private var groupChatStore: CommunityGroupChatStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore

    let group: CommunityGroup
    @State private var messages: [CommunityGroupChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var isCheckingImage = false
    @State private var isPhotoSharingUnavailable = false
    @State private var imageDraft: CommunityImageDraft?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pendingAttachmentID: UUID?
    @State private var pendingImage: UIImage?
    @State private var isPendingImageScan = false
    @State private var latestOwnMessageID: UUID?
    @State private var readReceipt: CommunityGroupChatReadReceipt?
    @State private var isMuted = false
    @State private var errorMessage: String?
    @State private var reportTarget: CommunityGroupChatMessage?
    @State private var hideTarget: CommunityGroupChatMessage?
    @State private var hasMoreOlderMessages = false
    @State private var isLoadingOlderMessages = false
    @StateObject private var realtimeDebouncer = NorgeTaskDebouncer()

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                NorgeSkeletonList(rowCount: 3, showsMedia: false)
                    .padding(.horizontal, 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
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
                            if let errorMessage {
                                NorgeInlineFeedback(message: errorMessage)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.last?.id) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                composer
            }
        }
        .background(Color.norgeAppBackground.ignoresSafeArea())
        .sheet(item: $imageDraft) { source in
            CommunityImageEditor(source: source) { data in
                imageDraft = nil
                await stageConfirmedImage(data)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.norgeAppBackground, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleMuted() }
                } label: {
                    Image(systemName: isMuted ? "bell" : "bell.slash")
                }
                .accessibilityLabel(AppStrings.localized(isMuted ? "chat.unmute" : "chat.mute"))
            }
        }
        .task {
            if let ownerID = authenticationStore.user?.id {
                await restorePendingImage(ownerID: ownerID)
            }
            await reload()
        }
        .task {
            let events = await groupChatStore.messageEvents(groupID: group.id)
            for await _ in events {
                guard !Task.isCancelled else { return }
                realtimeDebouncer.schedule(after: .milliseconds(200)) {
                    await refreshFromRealtime()
                }
            }
        }
        .task(id: pendingAttachmentID) { await pollPendingImageScan() }
        .onDisappear { realtimeDebouncer.cancel() }
        .refreshable { await reload(showSpinner: false) }
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

    private func bubble(_ message: CommunityGroupChatMessage) -> some View {
        let isMine = message.senderID == authenticationStore.user?.id
        return CommunityChatBubbleContainer(
            isMine: isMine,
            outgoingColor: Color.norgePrimary.opacity(0.16),
            cornerRadius: 16,
            horizontalPadding: 11,
            verticalPadding: 11
        ) {
            if !isMine {
                NavigationLink {
                    CommunityMemberProfileView(userID: message.senderID)
                } label: {
                    Text(message.displayName).font(.caption.weight(.semibold))
                }.buttonStyle(.plain)
            }
            if let attachmentID = message.attachmentID {
                CommunityChatAttachmentImage(attachmentID: attachmentID, viewerID: authenticationStore.user?.id) { id in
                    try? await groupChatStore.imageURL(attachmentID: id)
                }
            }
            if !message.body.isEmpty { Text(message.body).textSelection(.enabled) }
            if shouldShowReadReceipt(for: message) {
                Text(String(format: AppStrings.localized("messages.seen_by_count"), readReceipt?.seenCount ?? 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(AppStrings.localized("messages.seen"))
            }
            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
        } menu: {
            Button(AppStrings.localized("messages.delete_for_me"), systemImage: "eye.slash") { hideTarget = message }
            if !isMine {
                Button(
                    AppStrings.localized("messages.report_title"), systemImage: "exclamationmark.bubble",
                    role: .destructive
                ) { reportTarget = message }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPhotoSharingUnavailable {
                Label(
                    AppStrings.localized("groups.chat_photo_temporarily_unavailable"),
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)
            }
            if let pendingImage {
                HStack(spacing: 10) {
                    Image(uiImage: pendingImage)
                        .resizable().scaledToFill().frame(width: 54, height: 54).clipShape(
                            RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(
                        AppStrings.localized(
                            isPendingImageScan ? "groups.chat_image_checking" : "groups.chat_image_ready"
                        )
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        guard let attachmentID = pendingAttachmentID else { return }
                        pendingAttachmentID = nil
                        self.pendingImage = nil
                        isPendingImageScan = false
                        Task {
                            try? await groupChatStore.cancelImage(attachmentID: attachmentID)
                            if let ownerID = authenticationStore.user?.id {
                                await CommunityPendingImageStore.shared.remove(
                                    ownerID: ownerID, scopeID: group.id, kind: .group
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(AppStrings.localized("groups.chat_remove_image"))
                }
                .padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if !isPhotoSharingUnavailable {
                    let checkingImage = isCheckingImage
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        if checkingImage {
                            ProgressView().frame(width: 38, height: 44)
                        } else {
                            Image(systemName: "photo").font(.title3).frame(width: 38, height: 44)
                        }
                    }
                    .disabled(isSending || isCheckingImage)
                    .accessibilityLabel(AppStrings.localized("groups.chat_add_photo"))
                }
                TextField(AppStrings.localized("groups.chat_placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .norgeComposerInput()
                    .onChange(of: draft) { _, value in
                        let normalized = CommunityMessageDraft.removingLeadingWhitespace(value)
                        if normalized != value { draft = normalized }
                    }
                NorgeCircularSendButton(
                    isSending: isSending,
                    isEnabled: !isSending && !isCheckingImage && !isPendingImageScan
                        && (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            || pendingAttachmentID != nil),
                    accessibilityLabel: AppStrings.localized("chat.send")
                ) { Task { await send() } }
            }
        }
        .padding()
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await prepareImage(item) }
        }
    }

    private func reload(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }
        do {
            let page = try await groupChatStore.messagePage(groupID: group.id, before: nil)
            messages = page.items
            hasMoreOlderMessages = page.hasMoreOlder
            isMuted = (try? await groupChatStore.isMuted(groupID: group.id)) ?? false
            await groupChatStore.markRead(groupID: group.id)
            await refreshReadReceipt()
        } catch { errorMessage = AppStrings.localized("groups.chat_error") }
    }

    private func loadOlderMessages() async -> UUID? {
        guard !isLoadingOlderMessages, hasMoreOlderMessages, let oldest = messages.first else { return nil }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        do {
            let page = try await groupChatStore.messagePage(
                groupID: group.id,
                before: CommunityMessageCursor(createdAt: oldest.createdAt, id: oldest.id)
            )
            let knownIDs = Set(messages.map(\.id))
            let olderMessages = page.items.filter { !knownIDs.contains($0.id) }
            messages.insert(contentsOf: olderMessages, at: 0)
            hasMoreOlderMessages = page.hasMoreOlder
            return oldest.id
        } catch {
            errorMessage = AppStrings.localized("groups.chat_error")
            return nil
        }
    }

    private func refreshFromRealtime() async {
        guard let lastMessage = messages.last else {
            await reload(showSpinner: false)
            return
        }
        do {
            let delta = try await groupChatStore.messages(
                groupID: group.id,
                after: CommunityMessageCursor(createdAt: lastMessage.createdAt, id: lastMessage.id)
            )
            let knownIDs = Set(messages.map(\.id))
            let newMessages = delta.filter { !knownIDs.contains($0.id) }
            guard !newMessages.isEmpty else { return }
            messages.append(contentsOf: newMessages)
            if let viewerID = authenticationStore.user?.id,
                newMessages.contains(where: { $0.senderID != viewerID })
            {
                await groupChatStore.markRead(groupID: group.id)
            }
        } catch {
            errorMessage = AppStrings.localized("groups.chat_error")
        }
    }

    private func refreshReadReceipt() async {
        guard let message = messages.last(where: { $0.senderID == authenticationStore.user?.id }) else {
            latestOwnMessageID = nil
            readReceipt = nil
            return
        }
        latestOwnMessageID = message.id
        readReceipt = try? await groupChatStore.readReceipt(messageID: message.id)
    }

    private func shouldShowReadReceipt(for message: CommunityGroupChatMessage) -> Bool {
        message.id == latestOwnMessageID
            && readReceipt?.areReadReceiptsEnabled == true
            && (readReceipt?.seenCount ?? 0) > 0
    }

    private func send() async {
        guard !isPendingImageScan else { return }
        isSending = true
        defer { isSending = false }
        do {
            if let pendingAttachmentID {
                try await groupChatStore.send(
                    groupID: group.id, body: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachmentID: pendingAttachmentID)
            } else {
                try await groupChatStore.send(
                    groupID: group.id, body: draft.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            draft = ""
            pendingAttachmentID = nil
            pendingImage = nil
            isPendingImageScan = false
            if let ownerID = authenticationStore.user?.id {
                await CommunityPendingImageStore.shared.remove(
                    ownerID: ownerID, scopeID: group.id, kind: .group
                )
            }
            await refreshFromRealtime()
        } catch { errorMessage = AppStrings.localized("groups.chat_error") }
    }

    private func toggleMuted() async {
        let nextValue = !isMuted
        do {
            try await groupChatStore.updateMuted(groupID: group.id, isMuted: nextValue)
            isMuted = nextValue
        } catch {
            errorMessage = AppStrings.localized("groups.chat_error")
        }
    }

    private func prepareImage(_ item: PhotosPickerItem) async {
        isCheckingImage = true
        defer {
            isCheckingImage = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CommunityMediaError.unsupportedImage
            }
            imageDraft = CommunityImageDraft(data: data, aspect: .free)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? AppStrings.localized("groups.chat_image_error")
        } catch {
            errorMessage = AppStrings.localized("groups.chat_image_error")
        }
    }

    private func stageConfirmedImage(_ data: Data) async {
        isCheckingImage = true
        defer { isCheckingImage = false }
        do {
            let upload = try await CommunityImageProcessing.prepareJPEG(from: data)
            guard
                let image = CommunityImageDecoding.image(
                    from: upload.data, variant: .thumbnail(maxPixelDimension: 256)
                )
            else {
                throw CommunityMediaError.unsupportedImage
            }
            await stagePreparedImage(upload, image: image)
        } catch let error as CommunityGroupChatMediaError {
            handleImageError(error)
        } catch {
            errorMessage = AppStrings.localized("groups.chat_image_error")
        }
    }

    private func stagePreparedImage(_ upload: CommunityImageUpload, image: UIImage) async {
        do {
            let attachmentID = try await groupChatStore.stageImage(groupID: group.id, jpegData: upload.data)
            pendingAttachmentID = attachmentID
            pendingImage = image
            isPendingImageScan = false
        } catch let error as CommunityGroupChatMediaError {
            await handleStagedImageError(error, upload: upload, image: image)
        } catch {
            errorMessage = AppStrings.localized("groups.chat_image_error")
        }
    }

    private func handleStagedImageError(
        _ error: CommunityGroupChatMediaError,
        upload: CommunityImageUpload,
        image: UIImage
    ) async {
        switch error {
        case .pendingScan(let attachmentID):
            pendingAttachmentID = attachmentID
            pendingImage = image
            isPendingImageScan = true
            if let ownerID = authenticationStore.user?.id {
                await CommunityPendingImageStore.shared.save(
                    attachmentID: attachmentID,
                    ownerID: ownerID,
                    scopeID: group.id,
                    kind: .group,
                    jpegData: upload.data
                )
            }
        case .configurationMissing, .accessDenied, .unavailable:
            isPhotoSharingUnavailable = true
            errorMessage = AppStrings.localized("groups.chat_photo_temporarily_unavailable")
        case .rejected:
            errorMessage = AppStrings.localized("groups.chat_image_rejected")
        case .needsReview:
            errorMessage = AppStrings.localized("groups.chat_image_review")
        case .authenticationRequired:
            errorMessage = AppStrings.auth("sign_in_required")
        }
    }

    private func handleImageError(_ error: CommunityGroupChatMediaError) {
        switch error {
        case .unavailable, .configurationMissing:
            isPhotoSharingUnavailable = true
            errorMessage = AppStrings.localized("groups.chat_photo_temporarily_unavailable")
        default:
            errorMessage = error.errorDescription ?? AppStrings.localized("groups.chat_image_error")
        }
    }

    private func restorePendingImage(ownerID: UUID) async {
        guard
            let pending = await CommunityPendingImageStore.shared.load(
                ownerID: ownerID, scopeID: group.id, kind: .group
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
                let outcome = try await groupChatStore.scanStatus(attachmentID: attachmentID)
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
        try? await groupChatStore.cancelImage(attachmentID: attachmentID)
        if let ownerID = authenticationStore.user?.id {
            await CommunityPendingImageStore.shared.remove(
                ownerID: ownerID, scopeID: group.id, kind: .group
            )
        }
    }

    private func hide(_ message: CommunityGroupChatMessage) async {
        do {
            try await groupChatStore.hide(messageID: message.id)
            hideTarget = nil
            await reload(showSpinner: false)
        } catch { errorMessage = AppStrings.localized("groups.chat_error") }
    }

    private func report(_ message: CommunityGroupChatMessage, reason: CommunityReportReason) async {
        do {
            try await groupChatStore.report(messageID: message.id, reason: reason)
            reportTarget = nil
        } catch { errorMessage = AppStrings.localized("groups.chat_error") }
    }
}
