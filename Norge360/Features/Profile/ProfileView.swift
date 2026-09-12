import SwiftUI

// The profile tab intentionally owns its plan summary, settings and account
// actions in one navigation destination.
// swiftlint:disable file_length

struct ProfileView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore

    var body: some View {
        if let userID = authenticationStore.user?.id {
            CommunityMemberProfileView(userID: userID, usesRootTopBar: true)
        } else {
            NorgeLoadingState(fillsAvailableSpace: true)
        }
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var moderationStore: CommunityModerationStore
    @EnvironmentObject private var searchHistoryStore: CommunitySearchHistoryStore
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(AppStrings.localized("settings.search"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .norgeCapsuleInput(height: 46, horizontalPadding: 16)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            List {
                if matches("profile edit details visibility public private followers following likes liked posts") {
                    Section(AppStrings.localized("settings.profile_section")) {
                        if let profile = communityProfileStore.profile {
                            NavigationLink {
                                EditCommunityProfileDetailsView(profile: profile)
                            } label: {
                                Label(
                                    AppStrings.localized("profile.edit_details"), systemImage: "person.text.rectangle")
                            }
                        }
                        NavigationLink {
                            ProfileVisibilitySettingsView()
                        } label: {
                            Label(AppStrings.localized("profile.visibility"), systemImage: "eye")
                        }
                        NavigationLink {
                            FollowVisibilitySettingsView()
                        } label: {
                            Label(AppStrings.localized("follow.visibility_title"), systemImage: "person.2")
                        }
                        NavigationLink {
                            LikedPostsVisibilitySettingsView()
                        } label: {
                            Label(AppStrings.localized("likes.visibility_title"), systemImage: "heart")
                        }
                        Button(AppStrings.localized("settings.clear_search_history"), role: .destructive) {
                            searchHistoryStore.clear()
                        }
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                if matches("blocked members block") {
                    Section(AppStrings.localized("blocks.title")) {
                        NavigationLink {
                            BlockedMembersView()
                        } label: {
                            Label(AppStrings.localized("blocks.manage"), systemImage: "hand.raised.slash")
                        }

                        Text(AppStrings.localized("blocks.note"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                if matches("guidelines community rules safety") {
                    Section(AppStrings.localized("guidelines.section")) {
                        NavigationLink {
                            LegalDocumentView(document: .communityGuidelines)
                        } label: {
                            Label(AppStrings.localized("guidelines.title"), systemImage: "checklist")
                        }
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                if moderationStore.role != nil {
                    Section(AppStrings.localized("moderation.section")) {
                        NavigationLink {
                            CommunityModerationReviewView()
                        } label: {
                            Label(
                                AppStrings.localized("moderation.review_reports"), systemImage: "shield.lefthalf.filled"
                            )
                        }
                    }
                    .listRowBackground(Color.norgeAppBackground)
                } else if moderationStore.roleCheckFailed {
                    Section(AppStrings.localized("moderation.section")) {
                        Label(
                            AppStrings.localized("moderation.unavailable_title"), systemImage: "exclamationmark.shield")
                        Text(AppStrings.localized("moderation.unavailable_body"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let diagnostic = moderationStore.roleCheckDiagnostic {
                            Text(diagnostic)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Button(AppStrings.localized("moderation.retry")) {
                            Task { await moderationStore.refreshRole() }
                        }
                        .disabled(moderationStore.isCheckingRole)
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                if matches("notifications new followers new posts groups messages appearance language theme") {
                    Section(AppStrings.localized("settings.preferences_section")) {
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Label(AppStrings.localized("settings.notifications"), systemImage: "bell")
                        }
                        NavigationLink {
                            MessagePrivacySettingsView()
                        } label: {
                            Label(AppStrings.localized("messages.privacy_title"), systemImage: "message.badge")
                        }
                        NavigationLink {
                            AppearanceSettingsView()
                        } label: {
                            Label(AppStrings.localized("appearance.title"), systemImage: "circle.lefthalf.filled")
                        }
                        NavigationLink {
                            AppLanguageSettingsView()
                        } label: {
                            Label(AppStrings.localized("settings.language_title"), systemImage: "globe")
                        }
                    }
                    .listRowBackground(Color.norgeAppBackground)
                }
                if matches("account security password sign out") {
                    Section(AppStrings.auth("account")) {
                        NavigationLink {
                            AccountSecuritySettingsView()
                        } label: {
                            Label(AppStrings.localized("settings.account_security"), systemImage: "lock")
                        }
                        SignOutButton()
                    }
                    .listRowBackground(Color.norgeAppBackground)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 12)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("profile.settings"))
        .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            // A staff role can be granted while the app session is already
            // active. Refresh when Settings opens instead of requiring logout.
            await moderationStore.refreshRole()
        }
    }

    private func matches(_ terms: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return true }
        return terms.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
    }

}

extension AppAppearance {
    fileprivate var title: String {
        switch self {
        case .system:
            AppStrings.localized("appearance.system")
        case .light:
            AppStrings.localized("appearance.light")
        case .dark:
            AppStrings.localized("appearance.dark")
        }
    }
}

private struct ProfileVisibilitySettingsView: View {
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle(
                    AppStrings.localized("profile.public_profile"),
                    isOn: Binding(
                        get: { communityProfileStore.profile?.isPublic ?? true },
                        set: { value in Task { await updateVisibility(value) } }
                    )
                )
                .disabled(communityProfileStore.profile == nil || isUpdating)

                Text(
                    communityProfileStore.profile?.isPublic == false
                        ? AppStrings.localized("profile.private_profile_note")
                        : AppStrings.localized("profile.public_profile_note")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Toggle(
                    AppStrings.localized("profile.show_norway_status"),
                    isOn: Binding(
                        get: { communityProfileStore.profile?.showNorwayStatus != false },
                        set: { value in
                            let showLocation = communityProfileStore.profile?.showLocation != false
                            Task { await updateFieldVisibility(showNorwayStatus: value, showLocation: showLocation) }
                        }
                    )
                )
                .disabled(communityProfileStore.profile == nil || isUpdating)

                Toggle(
                    AppStrings.localized("profile.show_location"),
                    isOn: Binding(
                        get: { communityProfileStore.profile?.showLocation != false },
                        set: { value in
                            let showNorwayStatus = communityProfileStore.profile?.showNorwayStatus != false
                            Task {
                                await updateFieldVisibility(showNorwayStatus: showNorwayStatus, showLocation: value)
                            }
                        }
                    )
                )
                .disabled(communityProfileStore.profile == nil || isUpdating)
            }
            .listRowBackground(Color.norgeAppBackground)
            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("profile.visibility"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateVisibility(_ isPublic: Bool) async {
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            try await communityProfileStore.updateVisibility(isPublic: isPublic)
        } catch {
            errorMessage = AppStrings.localized("profile.visibility_error")
        }
    }

    private func updateFieldVisibility(showNorwayStatus: Bool, showLocation: Bool) async {
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            try await communityProfileStore.updateFieldVisibility(
                showNorwayStatus: showNorwayStatus,
                showLocation: showLocation
            )
        } catch {
            errorMessage = AppStrings.localized("profile.visibility_error")
        }
    }
}

private struct FollowVisibilitySettingsView: View {
    @EnvironmentObject private var followStore: CommunityFollowStore
    @State private var followersVisibility: CommunityFollowVisibility = .everyone
    @State private var followingVisibility: CommunityFollowVisibility = .everyone
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker(
                    AppStrings.localized("follow.followers"),
                    selection: binding(for: $followersVisibility)
                ) {
                    ForEach(CommunityFollowVisibility.allCases) { visibility in
                        Text(title(for: visibility)).tag(visibility)
                    }
                }
                Picker(
                    AppStrings.localized("follow.following"),
                    selection: binding(for: $followingVisibility)
                ) {
                    ForEach(CommunityFollowVisibility.allCases) { visibility in
                        Text(title(for: visibility)).tag(visibility)
                    }
                }
                Text(AppStrings.localized("follow.visibility_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)

            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("follow.visibility_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                try await followStore.loadVisibility()
                followersVisibility = followStore.visibility.followers
                followingVisibility = followStore.visibility.following
                errorMessage = nil
            } catch {
                errorMessage = AppStrings.localized("follow.visibility_error")
            }
            isLoading = false
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func binding(for value: Binding<CommunityFollowVisibility>) -> Binding<CommunityFollowVisibility> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                Task { await save() }
            }
        )
    }

    private func save() async {
        guard !isLoading, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await followStore.updateVisibility(
                CommunityFollowVisibilitySettings(
                    followers: followersVisibility,
                    following: followingVisibility
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.localized("follow.visibility_error")
        }
    }

    private func title(for visibility: CommunityFollowVisibility) -> String {
        AppStrings.localized("follow.visibility." + visibility.rawValue)
    }
}

private struct LikedPostsVisibilitySettingsView: View {
    @EnvironmentObject private var followStore: CommunityFollowStore
    @State private var visibility: CommunityLikedPostsVisibility = .onlyMe
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker(
                    AppStrings.localized("likes.visibility_title"),
                    selection: binding
                ) {
                    ForEach(CommunityLikedPostsVisibility.allCases) { value in
                        Text(title(for: value)).tag(value)
                    }
                }
                Text(AppStrings.localized("likes.visibility_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)

            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("likes.visibility_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                try await followStore.loadLikedPostsVisibility()
                visibility = followStore.likedPostsVisibility
                errorMessage = nil
            } catch {
                errorMessage = AppStrings.localized("likes.visibility_error")
            }
            isLoading = false
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private var binding: Binding<CommunityLikedPostsVisibility> {
        Binding(
            get: { visibility },
            set: { newValue in
                visibility = newValue
                Task { await save() }
            }
        )
    }

    private func save() async {
        guard !isLoading, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await followStore.updateLikedPostsVisibility(visibility)
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.localized("likes.visibility_error")
        }
    }

    private func title(for value: CommunityLikedPostsVisibility) -> String {
        AppStrings.localized("likes.visibility." + value.rawValue)
    }
}

private struct MessagePrivacySettingsView: View {
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle(
                    AppStrings.localized("messages.read_receipts"),
                    isOn: Binding(
                        get: { conversationsStore.readReceiptsEnabled },
                        set: { value in Task { await updateReadReceipts(value) } }
                    )
                )
                .disabled(isUpdating)

                Text(AppStrings.localized("messages.read_receipts_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)

            Section {
                Text(AppStrings.localized("messages.delete_for_me_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)

            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("messages.privacy_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await conversationsStore.loadReadReceiptPreference() }
    }

    private func updateReadReceipts(_ enabled: Bool) async {
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do { try await conversationsStore.updateReadReceipts(enabled: enabled) } catch {
            errorMessage = AppStrings.localized("messages.error")
        }
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettings

    var body: some View {
        List {
            Section {
                Picker("", selection: $appearanceSettings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Text(AppStrings.localized("appearance.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("appearance.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppLanguageSettingsView: View {
    @EnvironmentObject private var languageSettings: LanguageSettings
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker(
                    "",
                    selection: Binding(
                        get: { languageSettings.language },
                        set: { language in Task { await update(language) } }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(isUpdating || communityProfileStore.profile == nil)

                Text(AppStrings.localized("settings.language_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("settings.language_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ language: AppLanguage) async {
        guard language != languageSettings.language else { return }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        do {
            try await communityProfileStore.updatePreferredLanguage(language)
            languageSettings.language = language
        } catch {
            errorMessage = AppStrings.localized("settings.language_error")
        }
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var pushNotificationsStore: PushNotificationsStore
    @AppStorage("notifications.in_app_enabled") private var inAppEnabled = true
    @AppStorage("notifications.follow_enabled") private var followEnabled = true
    @AppStorage("notifications.activity_enabled") private var activityEnabled = true
    @AppStorage("notifications.group_enabled") private var groupEnabled = true
    @AppStorage("notifications.messages_enabled") private var messagesEnabled = true

    var body: some View {
        List {
            Section(AppStrings.localized("settings.notifications_in_app")) {
                Toggle(AppStrings.localized("settings.notifications_in_app_toggle"), isOn: $inAppEnabled)
                Text(AppStrings.localized("settings.notifications_in_app_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("settings.notifications_activity")) {
                Toggle(AppStrings.localized("settings.notifications_follows"), isOn: $followEnabled)
                    .disabled(!inAppEnabled)
                Toggle(AppStrings.localized("settings.notifications_posts"), isOn: $activityEnabled)
                    .disabled(!inAppEnabled)
                Toggle(AppStrings.localized("settings.notifications_groups"), isOn: $groupEnabled)
                    .disabled(!inAppEnabled)
                Toggle(AppStrings.localized("settings.notifications_messages"), isOn: $messagesEnabled)
                    .disabled(!inAppEnabled)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("settings.notifications_push")) {
                Toggle(
                    AppStrings.localized("settings.notifications_push_messages"),
                    isOn: Binding(
                        get: { pushNotificationsStore.messagePushEnabled },
                        set: { enabled in
                            Task { try? await pushNotificationsStore.updateMessagePushEnabled(enabled) }
                        }
                    )
                )
                Text(AppStrings.localized("settings.notifications_push_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(AppStrings.localized("settings.notifications_push_retry")) {
                    Task { await pushNotificationsStore.retryRegistration() }
                }
                if let registrationErrorMessage = pushNotificationsStore.registrationErrorMessage {
                    NorgeInlineFeedback(message: registrationErrorMessage)
                }
            }
            .listRowBackground(Color.norgeAppBackground)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("settings.notifications"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountSecuritySettingsView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore

    var body: some View {
        List {
            Section(AppStrings.auth("account")) {
                if let email = authenticationStore.user?.email {
                    LabeledContent(AppStrings.auth("email"), value: email)
                }
                NavigationLink {
                    ChangeEmailView()
                } label: {
                    Label(AppStrings.localized("settings.change_email"), systemImage: "envelope")
                }
                NavigationLink {
                    ChangePasswordView()
                } label: {
                    Label(AppStrings.localized("settings.change_password"), systemImage: "key")
                }
            }
            .listRowBackground(Color.norgeAppBackground)
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("settings.account_security"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChangeEmailView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var email = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField(AppStrings.auth("email"), text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                Text(AppStrings.localized("settings.change_email_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
            if let message {
                Section { Text(message).foregroundStyle(.green) }.listRowBackground(Color.norgeAppBackground)
            }
            if let errorMessage { NorgeFormErrorSection(message: errorMessage) }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("settings.change_email"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("settings.save")) { Task { await save() } }
                    .disabled(!isValid || isSaving)
            }
            .norgePlainToolbar()
        }
    }

    private var isValid: Bool {
        let candidate = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.contains("@") && candidate.contains(".")
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await authenticationStore.updateEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
            message = AppStrings.localized("settings.change_email_sent")
        } catch {
            errorMessage = AppStrings.localized("settings.change_email_error")
        }
    }
}

private struct ChangePasswordView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField(AppStrings.auth("new_password"), text: $password)
                    .textContentType(.newPassword)
                SecureField(AppStrings.auth("confirm_password"), text: $confirmation)
                    .textContentType(.newPassword)
                Text(AppStrings.localized("settings.change_password_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
            if let errorMessage { NorgeFormErrorSection(message: errorMessage) }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("settings.change_password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("settings.save")) { Task { await save() } }
                    .disabled(!canSave || isSaving)
            }
            .norgePlainToolbar()
        }
    }

    private var canSave: Bool { password.count >= 8 && password == confirmation }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await authenticationStore.updatePassword(password)
            dismiss()
        } catch {
            errorMessage = AppStrings.localized("settings.change_password_error")
        }
    }
}

struct EditCommunityProfileDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore

    let profile: CommunityProfile
    @State private var displayName: String
    @State private var username: String
    @State private var norwayStatus: NorwayStatus
    @State private var cityOrRegion: String
    @State private var biography: String
    @State private var interests: Set<CommunityInterest>
    @State private var usernameAvailability: ProfileUsernameAvailability = .idle
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: CommunityProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username)
        _norwayStatus = State(initialValue: profile.norwayStatus ?? .resident)
        _cityOrRegion = State(initialValue: profile.cityOrRegion ?? "")
        _biography = State(initialValue: profile.biography ?? "")
        _interests = State(initialValue: Set(profile.interests.compactMap(CommunityInterest.init(rawValue:))))
    }

    var body: some View {
        Form {
            Section(AppStrings.localized("profile.identity_section")) {
                TextField(
                    AppStrings.localized("account_setup.display_name"),
                    text: limited($displayName, to: CommunityContentRules.maximumDisplayNameLength)
                )
                .textContentType(.nickname)
                .textInputAutocapitalization(.words)

                TextField(
                    AppStrings.localized("account_setup.username"),
                    text: limited($username, to: CommunityUsernameRules.maximumLength)
                )
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                usernameAvailabilityView
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("account_setup.norway_section")) {
                Picker(AppStrings.localized("account_setup.norway_status"), selection: $norwayStatus) {
                    ForEach(NorwayStatus.allCases) { status in
                        Text(norwayStatusTitle(status)).tag(status)
                    }
                }
                TextField(
                    AppStrings.localized("account_setup.city_or_region"),
                    text: limited($cityOrRegion, to: CommunityContentRules.maximumCityOrRegionLength)
                )
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section("Biography") {
                TextEditor(text: $biography)
                    .frame(minHeight: 90)
                    .onChange(of: biography) { _, value in
                        if value.count > CommunityContentRules.maximumBiographyLength {
                            biography = String(value.prefix(CommunityContentRules.maximumBiographyLength))
                        }
                    }
                Text("\(biography.count) / \(CommunityContentRules.maximumBiographyLength)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.localized("account_setup.interests_section")) {
                ForEach(CommunityInterest.allCases) { interest in
                    Toggle(
                        interestTitle(interest),
                        isOn: Binding(
                            get: { interests.contains(interest) },
                            set: { isSelected in
                                if isSelected { interests.insert(interest) } else { interests.remove(interest) }
                            }
                        ))
                }
            }
            .listRowBackground(Color.norgeAppBackground)

            if appState.plan != nil {
                Section(AppStrings.profileAnswers) {
                    NavigationLink {
                        RelocationAnswersEditorView()
                    } label: {
                        Label(
                            AppStrings.localized("profile.edit_answers"),
                            systemImage: "list.bullet.rectangle.portrait"
                        )
                    }
                }
                .listRowBackground(Color.norgeAppBackground)
            }

            if let errorMessage {
                NorgeFormErrorSection(message: errorMessage)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("profile.edit_details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("groups.save")) { Task { await save() } }
                    .disabled(!canSave || isSaving)
            }
            .norgePlainToolbar()
        }
        .task { await appState.activate() }
        .task(id: username) { await checkUsernameAvailability() }
    }

    private var canSave: Bool {
        CommunityContentRules.normalizedDisplayName(displayName) != nil
            && (username == profile.username || usernameAvailability == .available)
    }

    private func checkUsernameAvailability() async {
        guard let normalized = CommunityUsernameRules.normalized(username) else {
            usernameAvailability = .unavailable
            return
        }
        if normalized == profile.username {
            usernameAvailability = .idle
            return
        }
        usernameAvailability = .checking
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            usernameAvailability =
                try await communityProfileStore.isUsernameAvailable(normalized) ? .available : .unavailable
        } catch is CancellationError {
            return
        } catch {
            usernameAvailability = .unavailable
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await communityProfileStore.updateDetails(
                CommunityProfileDetailsInput(
                    displayName: displayName,
                    username: username,
                    norwayStatus: norwayStatus,
                    cityOrRegion: cityOrRegion,
                    biography: biography,
                    interests: interests
                )
            )
            dismiss()
        } catch {
            errorMessage = AppStrings.localized("profile.details_error")
        }
    }

    private func norwayStatusTitle(_ status: NorwayStatus) -> String {
        AppStrings.localized("community.status.\(status.rawValue)")
    }

    private func interestTitle(_ interest: CommunityInterest) -> String {
        AppStrings.localized("community.interest.\(interest.rawValue)")
    }

    private func limited(_ value: Binding<String>, to maximum: Int) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = String($0.prefix(maximum)) })
    }

    @ViewBuilder private var usernameAvailabilityView: some View {
        switch usernameAvailability {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text(AppStrings.localized("account_setup.username_checking"))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .available:
            Label(AppStrings.localized("account_setup.username_available"), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .unavailable:
            Label(AppStrings.localized("account_setup.username_unavailable"), systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

private struct RelocationAnswersEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var citizenship: String
    @State private var isEEACitizen: Bool
    @State private var currentlyInNorway: Bool
    @State private var movingReason: MovingReason
    @State private var stayDuration: StayDuration
    @State private var destinationCity: String
    @State private var householdType: HouseholdType
    @State private var hasJobOffer: Bool
    @State private var hasLoadedProfile = false

    init() {
        _citizenship = State(initialValue: "")
        _isEEACitizen = State(initialValue: false)
        _currentlyInNorway = State(initialValue: false)
        _movingReason = State(initialValue: .other)
        _stayDuration = State(initialValue: .undecided)
        _destinationCity = State(initialValue: "")
        _householdType = State(initialValue: .alone)
        _hasJobOffer = State(initialValue: false)
    }

    var body: some View {
        Group {
            if let plan = appState.plan {
                form
                    .onAppear {
                        load(plan.profile)
                    }
            } else {
                NorgeUnavailableState(
                    AppStrings.profileAnswers,
                    systemImage: "list.bullet.rectangle",
                    description: AppStrings.localized("profile.answers_unavailable")
                )
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.profileAnswers)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("settings.save")) {
                    save()
                }
            }
            .norgePlainToolbar()
        }
        .task { await appState.activate() }
    }

    private var form: some View {
        Form {
            Section {
                TextField(AppStrings.profileCitizenship, text: $citizenship)
                    .textInputAutocapitalization(.words)
                Toggle(AppStrings.profileEEA, isOn: $isEEACitizen)
                Toggle(AppStrings.profileInNorway, isOn: $currentlyInNorway)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section {
                Picker(AppStrings.profileReason, selection: $movingReason) {
                    ForEach(MovingReason.allCases) { reason in
                        Text(reason.title).tag(reason)
                    }
                }
                Picker(AppStrings.profileStay, selection: $stayDuration) {
                    ForEach(StayDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                TextField(AppStrings.profileCity, text: $destinationCity)
                    .textInputAutocapitalization(.words)
                Picker(AppStrings.profileHousehold, selection: $householdType) {
                    ForEach(HouseholdType.allCases) { household in
                        Text(household.title).tag(household)
                    }
                }
                Toggle(AppStrings.profileJobOffer, isOn: $hasJobOffer)
            }
            .listRowBackground(Color.norgeAppBackground)
        }
        .scrollContentBackground(.hidden)
    }

    private func load(_ profile: RelocationProfile) {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true
        citizenship = profile.citizenship
        isEEACitizen = profile.isEEACitizen
        currentlyInNorway = profile.currentlyInNorway
        movingReason = profile.movingReason
        stayDuration = profile.stayDuration
        destinationCity = profile.destinationCity
        householdType = profile.householdType
        hasJobOffer = profile.hasJobOffer
    }

    private func save() {
        let trimmedCitizenship = citizenship.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = destinationCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCitizenship.isEmpty, !trimmedCity.isEmpty else { return }
        appState.updateProfile(
            RelocationProfile(
                citizenship: trimmedCitizenship,
                isEEACitizen: isEEACitizen,
                currentlyInNorway: currentlyInNorway,
                movingReason: movingReason,
                stayDuration: stayDuration,
                destinationCity: trimmedCity,
                householdType: householdType,
                hasJobOffer: hasJobOffer
            )
        )
        dismiss()
    }
}

private enum ProfileUsernameAvailability: Equatable {
    case idle
    case checking
    case available
    case unavailable
}

private struct BlockedMembersView: View {
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @State private var isPresentingBlockSearch = false
    @State private var memberPendingUnblock: CommunityBlockedMember?

    var body: some View {
        Group {
            if feedStore.isLoadingBlockedMembers && feedStore.blockedMembers.isEmpty {
                NorgeLoadingState()
            } else if feedStore.blockedMembers.isEmpty {
                NorgeUnavailableState(
                    AppStrings.localized("blocks.empty_title"),
                    systemImage: "hand.raised.slash",
                    description: AppStrings.localized("blocks.empty_body")
                )
            } else {
                List {
                    ForEach(feedStore.blockedMembers) { member in
                        HStack(spacing: 12) {
                            CommunityMemberIdentityView(
                                displayName: member.displayName,
                                username: member.username,
                                avatarURL: member.avatarURL,
                                nameFont: .headline
                            )
                            Spacer()
                            Button(AppStrings.localized("blocks.unblock")) {
                                memberPendingUnblock = member
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(
                                String(format: AppStrings.localized("blocks.unblock_member"), member.displayName)
                            )
                        }
                        .accessibilityElement(children: .combine)
                        .listRowBackground(Color.norgeAppBackground)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("blocks.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingBlockSearch = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppStrings.localized("blocks.add_member"))
            }
        }
        .task { await feedStore.loadBlockedMembers() }
        .sheet(isPresented: $isPresentingBlockSearch) {
            BlockMemberSearchView()
        }
        .overlay {
            if let message = feedStore.errorMessage ?? feedStore.noticeMessage {
                NorgeInlineFeedback(
                    message: message,
                    kind: feedStore.errorMessage == nil ? .notice : .error
                )
            }
        }
        .alert(
            AppStrings.localized("blocks.unblock_confirm_title"),
            isPresented: Binding(
                get: { memberPendingUnblock != nil },
                set: { if !$0 { memberPendingUnblock = nil } }
            )
        ) {
            if let member = memberPendingUnblock {
                Button(AppStrings.localized("blocks.unblock"), role: .destructive) {
                    let userID = member.userID
                    memberPendingUnblock = nil
                    Task { await feedStore.unblock(userID: userID) }
                }
            }
            Button(AppStrings.localized("common.cancel"), role: .cancel) {}
        } message: {
            if let member = memberPendingUnblock {
                Text(String(format: AppStrings.localized("blocks.unblock_confirm_body"), member.displayName))
            }
        }
    }
}

private struct BlockMemberSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @State private var query = ""
    @State private var blockingIDs: Set<UUID> = []
    @State private var profilePendingBlock: CommunityProfile?

    private var profiles: [CommunityProfile] {
        searchStore.results.profiles.filter { profile in
            profile.userID != authenticationStore.user?.id
                && !feedStore.blockedMembers.contains(where: { $0.userID == profile.userID })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    NorgeUnavailableState(
                        AppStrings.localized("blocks.search_title"),
                        systemImage: "magnifyingglass",
                        description: AppStrings.localized("blocks.search_body")
                    )
                } else if searchStore.isSearching {
                    NorgeLoadingState(minimumHeight: 200)
                } else if profiles.isEmpty {
                    NorgeUnavailableState(
                        AppStrings.localized("blocks.search_empty"), systemImage: "person.crop.circle.badge.question")
                } else {
                    List(profiles) { profile in
                        HStack(spacing: 12) {
                            CommunityMemberIdentityView(
                                displayName: profile.displayName,
                                username: profile.username,
                                avatarURL: profile.avatarURL,
                                nameFont: .headline
                            )
                            Spacer()
                            Button(AppStrings.localized("blocks.block")) {
                                profilePendingBlock = profile
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(blockingIDs.contains(profile.userID))
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: AppStrings.localized("blocks.search_prompt"))
            .navigationTitle(AppStrings.localized("blocks.add_member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("common.cancel")) { dismiss() }
                }
            }
            .overlay {
                if let message = feedStore.errorMessage ?? feedStore.noticeMessage {
                    NorgeInlineFeedback(
                        message: message,
                        kind: feedStore.errorMessage == nil ? .notice : .error
                    )
                }
            }
            .alert(
                AppStrings.localized("blocks.block_confirm_title"),
                isPresented: Binding(
                    get: { profilePendingBlock != nil },
                    set: { if !$0 { profilePendingBlock = nil } }
                )
            ) {
                if let profile = profilePendingBlock {
                    Button(AppStrings.localized("blocks.block"), role: .destructive) {
                        let selectedProfile = profile
                        profilePendingBlock = nil
                        Task { await block(selectedProfile) }
                    }
                }
                Button(AppStrings.localized("common.cancel"), role: .cancel) {}
            } message: {
                if let profile = profilePendingBlock {
                    Text(String(format: AppStrings.localized("blocks.block_confirm_body"), profile.displayName))
                }
            }
            .task(id: query) {
                guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
                    searchStore.clear()
                    return
                }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                await searchStore.search(query: query)
            }
        }
    }

    private func block(_ profile: CommunityProfile) async {
        blockingIDs.insert(profile.userID)
        defer { blockingIDs.remove(profile.userID) }
        guard await feedStore.block(authorID: profile.userID) else { return }
        await feedStore.loadBlockedMembers()
        dismiss()
    }
}
