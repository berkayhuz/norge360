import PhotosUI
import SwiftUI

struct CommunityConversationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    let conversation: CommunityConversationSummary
    let search: () -> Void
    let onBlocked: () -> Void
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsBlockConfirmation = false
    @State private var showsReportReasons = false
    @State private var reportSent = false
    @State private var backgroundPickerItem: PhotosPickerItem?
    @State private var customBackgroundData: Data?
    @State private var showsCamera = false

    private var settings: CommunityConversationSettings { conversationsStore.settings(for: conversation.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CommunityMemberProfileView(userID: conversation.otherUserID)
                    } label: {
                        CommunityMemberIdentityView(
                            displayName: conversation.displayName,
                            username: conversation.username,
                            avatarURL: conversation.avatarURL,
                            avatarSize: 58,
                            nameFont: .headline,
                            spacing: 14,
                            textSpacing: 4
                        )
                        .padding(.vertical, 6)
                    }
                    Button(action: search) {
                        Label(AppStrings.localized("chat.search_messages"), systemImage: "magnifyingglass")
                    }
                }.listRowBackground(Color.norgeAppBackground)
                Section {
                    Picker(AppStrings.localized("chat.background"), selection: binding(\.backgroundStyle)) {
                        ForEach(["plain", "dots", "grid"], id: \.self) { style in
                            Text(AppStrings.localized("chat.background.\(style)")).tag(style)
                        }
                    }
                    Picker(AppStrings.localized("chat.bubble_color"), selection: binding(\.bubbleColor)) {
                        ForEach(["teal", "blue", "purple", "neutral"], id: \.self) { color in
                            Text(AppStrings.localized("chat.color.\(color)")).tag(color)
                        }
                    }
                    PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                        Label(AppStrings.localized("chat.choose_background_photo"), systemImage: "photo")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showsCamera = true
                        } label: {
                            Label(AppStrings.localized("chat.take_background_photo"), systemImage: "camera")
                        }
                    }
                    if customBackgroundData != nil {
                        Button(AppStrings.localized("chat.remove_background_photo"), role: .destructive) {
                            customBackgroundData = nil
                            guard let userID = authenticationStore.user?.id else { return }
                            Task {
                                await CommunityChatBackgroundImageStore.shared.remove(
                                    for: conversation.id, userID: userID
                                )
                            }
                        }
                    }
                    ZStack {
                        CommunityChatBackdrop(style: settings.backgroundStyle, customImageData: customBackgroundData)
                        HStack {
                            Spacer()
                            Text(AppStrings.localized("chat.appearance_preview"))
                                .font(.subheadline).padding(.horizontal, 15).padding(.vertical, 12)
                                .background(
                                    CommunityChatPalette.color(settings.bubbleColor).opacity(0.23),
                                    in: RoundedRectangle(cornerRadius: 20))
                        }.padding(18)
                    }.frame(height: 95).clipShape(RoundedRectangle(cornerRadius: 16))
                } header: {
                    Text(AppStrings.localized("chat.appearance"))
                } footer: {
                    Text(AppStrings.localized("chat.appearance_note"))
                }
                .listRowBackground(Color.norgeAppBackground)

                Section {
                    NavigationLink {
                        CommunityConversationMediaView(conversation: conversation)
                    } label: {
                        Label(AppStrings.localized("chat.shared_media"), systemImage: "photo.on.rectangle.angled")
                    }
                }
                .listRowBackground(Color.norgeAppBackground)

                Section {
                    Toggle(isOn: binding(\.isMuted)) {
                        Label(AppStrings.localized("chat.mute"), systemImage: "bell.slash")
                    }
                    Toggle(isOn: binding(\.isRestricted)) {
                        Label(AppStrings.localized("chat.restrict"), systemImage: "hand.raised")
                    }
                } header: {
                    Text(AppStrings.localized("chat.privacy"))
                } footer: {
                    Text(AppStrings.localized("chat.restriction_note"))
                }
                .listRowBackground(Color.norgeAppBackground)

                Section {
                    HStack {
                        Label(AppStrings.localized("chat.timed_messages"), systemImage: "timer")
                        Spacer()
                        Text(AppStrings.localized("chat.unavailable")).foregroundStyle(.secondary).font(.caption)
                    }
                } footer: {
                    Text(AppStrings.localized("chat.retention_note"))
                }
                .listRowBackground(Color.norgeAppBackground)

                Section {
                    Button(role: .destructive) {
                        showsBlockConfirmation = true
                    } label: {
                        Label(AppStrings.localized("feed.block"), systemImage: "person.crop.circle.badge.xmark")
                    }
                    Button(role: .destructive) {
                        showsReportReasons = true
                    } label: {
                        Label(AppStrings.localized("chat.report_member"), systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text(AppStrings.localized("chat.safety"))
                } footer: {
                    Text(AppStrings.localized("chat.report_note"))
                }
                .listRowBackground(Color.norgeAppBackground)
                if let errorMessage {
                    NorgeFormErrorSection(message: errorMessage)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .disabled(isSaving)
            .navigationTitle(AppStrings.localized("chat.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(AppStrings.localized("chat.close"))
                }.norgePlainToolbar()
            }
            .overlay {
                if isSaving {
                    ProgressView().padding(16).background(
                        Color.norgeAppBackground, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .task {
                guard let userID = authenticationStore.user?.id else { return }
                customBackgroundData = await CommunityChatBackgroundImageStore.shared.imageData(
                    for: conversation.id, userID: userID
                )
            }
            .onChange(of: backgroundPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        guard let userID = authenticationStore.user?.id else { return }
                        await CommunityChatBackgroundImageStore.shared.save(
                            data, for: conversation.id, userID: userID
                        )
                        customBackgroundData = data
                    }
                    backgroundPickerItem = nil
                }
            }
            .sheet(isPresented: $showsCamera) {
                CameraImagePicker { data in
                    Task {
                        guard let userID = authenticationStore.user?.id else { return }
                        await CommunityChatBackgroundImageStore.shared.save(
                            data, for: conversation.id, userID: userID
                        )
                        customBackgroundData = data
                    }
                }
            }
            .confirmationDialog(AppStrings.localized("feed.block"), isPresented: $showsBlockConfirmation) {
                Button(AppStrings.localized("feed.block"), role: .destructive) {
                    Task {
                        isSaving = true
                        if await feedStore.block(authorID: conversation.otherUserID) {
                            await conversationsStore.reload()
                            dismiss()
                            onBlocked()
                        } else {
                            errorMessage = AppStrings.localized("messages.error")
                        }
                        isSaving = false
                    }
                }
            } message: {
                Text(AppStrings.localized("chat.block_note"))
            }
            .confirmationDialog(AppStrings.localized("chat.report_member"), isPresented: $showsReportReasons) {
                ForEach(CommunityReportReason.allCases) { reason in
                    Button(AppStrings.localized("feed.report_reason.\(reason.rawValue)")) {
                        Task {
                            isSaving = true
                            if await feedStore.report(profileID: conversation.otherUserID, reason: reason) {
                                reportSent = true
                            } else {
                                errorMessage = AppStrings.localized("messages.error")
                            }
                            isSaving = false
                        }
                    }
                }
            }
            .alert(AppStrings.localized("chat.report_received"), isPresented: $reportSent) {
                Button(AppStrings.localized("chat.close"), role: .cancel) {}
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CommunityConversationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                Task {
                    isSaving = true
                    defer { isSaving = false }
                    do {
                        try await conversationsStore.updateSettings(updated)
                        errorMessage = nil
                    } catch { errorMessage = AppStrings.localized("chat.settings_error") }
                }
            })
    }
}

private struct CommunityConversationMediaView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    let conversation: CommunityConversationSummary

    @State private var mediaMessages: [CommunityMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState()
            } else if let errorMessage {
                VStack(spacing: 0) {
                    NorgeInlineFeedback(message: errorMessage)
                    NorgeUnavailableState(
                        AppStrings.localized("chat.shared_media"),
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
            } else if mediaMessages.isEmpty {
                NorgeUnavailableState(
                    AppStrings.localized("chat.shared_media"),
                    systemImage: "photo.on.rectangle.angled",
                    description: AppStrings.localized("chat.shared_media_empty")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(mediaMessages) { message in
                            if let attachmentID = message.attachmentID {
                                CommunityChatAttachmentImage(
                                    attachmentID: attachmentID,
                                    viewerID: authenticationStore.user?.id,
                                    loadURL: { id in try? await conversationsStore.imageURL(attachmentID: id) }
                                )
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                            }
                        }
                    }
                    .padding(12)
                }
                .refreshable { await load() }
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("chat.shared_media"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = mediaMessages.isEmpty
        do {
            let messages = try await conversationsStore.messages(conversationID: conversation.id)
            mediaMessages = messages.filter {
                guard $0.attachmentID != nil else { return false }
                return $0.attachmentMimeType?.hasPrefix("image/") ?? true
            }
            errorMessage = nil
        } catch {
            if mediaMessages.isEmpty {
                errorMessage = AppStrings.localized("messages.error")
            }
        }
        isLoading = false
    }
}

enum CommunityChatPalette {
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "purple": .purple
        case "neutral": .gray
        default: .norgePrimary
        }
    }
}

/// Every style keeps the shared app background, including #252525 in dark mode.
/// Patterns customize a conversation without introducing a black canvas.
struct CommunityChatBackdrop: View {
    let style: String
    var customImageData: Data?
    var body: some View {
        Color.norgeAppBackground.overlay {
            if let customImageData, let image = UIImage(data: customImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.norgeAppBackground.opacity(0.18))
                    .clipped()
            }
            if style != "plain" {
                Canvas { context, size in
                    let spacing: CGFloat = style == "grid" ? 34 : 26
                    var path = Path()
                    for horizontalPosition in stride(from: CGFloat(0), through: size.width, by: spacing) {
                        if style == "grid" {
                            path.move(to: CGPoint(x: horizontalPosition, y: 0))
                            path.addLine(to: CGPoint(x: horizontalPosition, y: size.height))
                        } else {
                            for verticalPosition in stride(from: CGFloat(0), through: size.height, by: spacing) {
                                path.addEllipse(
                                    in: CGRect(x: horizontalPosition, y: verticalPosition, width: 2, height: 2)
                                )
                            }
                        }
                    }
                    if style == "grid" {
                        for verticalPosition in stride(from: CGFloat(0), through: size.height, by: spacing) {
                            path.move(to: CGPoint(x: 0, y: verticalPosition))
                            path.addLine(to: CGPoint(x: size.width, y: verticalPosition))
                        }
                        context.stroke(path, with: .color(.secondary.opacity(0.07)), lineWidth: 0.5)
                    } else {
                        context.fill(path, with: .color(.secondary.opacity(0.14)))
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }.ignoresSafeArea()
    }
}
