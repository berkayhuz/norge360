import SwiftUI

@main
struct Norge360App: App {
    @UIApplicationDelegateAdaptor(Norge360AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var languageSettings: LanguageSettings
    @StateObject private var appearanceSettings: AppearanceSettings
    @StateObject private var authenticationStore: AuthenticationStore
    @StateObject private var sessionCoordinator: SessionCoordinator
    @StateObject private var accountSetupStore: AccountSetupStore
    @StateObject private var communityProfileStore: CommunityProfileStore
    @StateObject private var communityGroupsStore: CommunityGroupsStore
    @StateObject private var communityFeedStore: CommunityFeedStore
    @StateObject private var communityFollowStore: CommunityFollowStore
    @StateObject private var communityNotificationsStore: CommunityNotificationsStore
    @StateObject private var pushNotificationsStore: PushNotificationsStore
    @StateObject private var communityConversationsStore: CommunityConversationsStore
    @StateObject private var communityGroupChatStore: CommunityGroupChatStore
    @StateObject private var communitySearchStore: CommunitySearchStore
    @StateObject private var communityEventsStore: CommunityEventsStore
    @StateObject private var moderationStore: CommunityModerationStore
    @StateObject private var tabRouter = AppTabRouter()
    @StateObject private var searchHistoryStore = CommunitySearchHistoryStore()

    // Dependency wiring is intentionally centralized at the application root.
    // swiftlint:disable:next function_body_length
    init() {
        NorgeAppearance.configure()
        let supabaseClient = SupabaseClientFactory.make()
        _appState = StateObject(
            wrappedValue: AppState(
                store: ProtectedFilePlanStore.shared,
                syncService: SupabasePlanSyncService(client: supabaseClient)
            ))
        _languageSettings = StateObject(wrappedValue: LanguageSettings())
        _appearanceSettings = StateObject(wrappedValue: AppearanceSettings())
        let authenticationStore = AuthenticationStore(service: SupabaseAuthService(client: supabaseClient))
        let pushNotificationsStore = PushNotificationsStore(
            service: CommunityPushNotificationService(client: supabaseClient)
        )
        _authenticationStore = StateObject(wrappedValue: authenticationStore)
        _sessionCoordinator = StateObject(
            wrappedValue: SessionCoordinator(
                authentication: authenticationStore,
                deviceDeactivation: pushNotificationsStore,
                accountDeletion: AccountDeletionService(client: supabaseClient),
                accountDataExport: AccountDataExportService(client: supabaseClient)
            ))
        _accountSetupStore = StateObject(
            wrappedValue: AccountSetupStore(
                service: AccountSetupService(client: supabaseClient)
            ))
        _communityProfileStore = StateObject(
            wrappedValue: CommunityProfileStore(
                service: CommunityProfileService(client: supabaseClient)
            ))
        _communityGroupsStore = StateObject(
            wrappedValue: CommunityGroupsStore(
                service: CommunityGroupsService(client: supabaseClient)
            ))
        _communityFeedStore = StateObject(
            wrappedValue: CommunityFeedStore(
                service: CommunityFeedService(client: supabaseClient)
            ))
        _communityFollowStore = StateObject(
            wrappedValue: CommunityFollowStore(
                service: CommunityFollowService(client: supabaseClient)
            ))
        _communityNotificationsStore = StateObject(
            wrappedValue: CommunityNotificationsStore(
                service: CommunityNotificationService(client: supabaseClient)
            ))
        _pushNotificationsStore = StateObject(wrappedValue: pushNotificationsStore)
        _communityConversationsStore = StateObject(
            wrappedValue: CommunityConversationsStore(
                service: CommunityConversationService(
                    client: supabaseClient,
                    mediaService: CommunityDirectChatMediaService(client: supabaseClient)
                )
            ))
        _communityGroupChatStore = StateObject(
            wrappedValue: CommunityGroupChatStore(
                service: CommunityGroupChatService(
                    client: supabaseClient,
                    mediaService: CommunityGroupChatMediaService(client: supabaseClient)
                )
            ))
        _communitySearchStore = StateObject(
            wrappedValue: CommunitySearchStore(
                service: CommunitySearchService(client: supabaseClient)
            ))
        _communityEventsStore = StateObject(
            wrappedValue: CommunityEventsStore(
                service: CommunityEventsService(client: supabaseClient)
            ))
        _moderationStore = StateObject(
            wrappedValue: CommunityModerationStore(
                service: CommunityModerationService(client: supabaseClient)
            ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(languageSettings)
                .environmentObject(appearanceSettings)
                .environmentObject(authenticationStore)
                .environmentObject(sessionCoordinator)
                .environmentObject(accountSetupStore)
                .environmentObject(communityProfileStore)
                .environmentObject(communityGroupsStore)
                .environmentObject(communityFeedStore)
                .environmentObject(communityFollowStore)
                .environmentObject(communityNotificationsStore)
                .environmentObject(pushNotificationsStore)
                .environmentObject(communityConversationsStore)
                .environmentObject(communityGroupChatStore)
                .environmentObject(communitySearchStore)
                .environmentObject(communityEventsStore)
                .environmentObject(moderationStore)
                .environmentObject(tabRouter)
                .environmentObject(searchHistoryStore)
                .environment(\.locale, languageSettings.language.locale)
                .environment(
                    \.layoutDirection,
                    languageSettings.language.isRightToLeft ? .rightToLeft : .leftToRight
                )
                .preferredColorScheme(appearanceSettings.appearance.preferredColorScheme)
                .id(appearanceSettings.appearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onOpenURL { url in
                    guard AuthCallbackURL.isValid(url) else { return }
                    authenticationStore.handleCallbackURL(url)
                }
                .onChange(of: authenticationStore.user, initial: true) { _, user in
                    updateFeatureStores(for: user)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Activate the notification lifecycle once the app is
                    // foregrounded. Realtime remains the primary update path.
                    guard phase == .active, authenticationStore.isAuthenticated else { return }
                    Task { await communityNotificationsStore.activate() }
                }
        }
    }

    private func updateFeatureStores(for user: AuthenticatedUser?) {
        appState.updateAuthenticatedUser(user)
        accountSetupStore.updateAuthenticatedUser(user)
        communityProfileStore.updateAuthenticatedUser(user)
        // Feature stores reset identity here, but defer network and Realtime
        // activation until their surfaces become visible.
        communityGroupsStore.updateAuthenticatedUser(user)
        communityFeedStore.updateAuthenticatedUser(user)
        communityFollowStore.updateAuthenticatedUser(user)
        communityNotificationsStore.updateAuthenticatedUser(user)
        pushNotificationsStore.updateAuthenticatedUser(user)
        communityConversationsStore.updateAuthenticatedUser(user)
        communityGroupChatStore.updateAuthenticatedUser(user)
        communityEventsStore.updateAuthenticatedUser(user)
        moderationStore.updateAuthenticatedUser(user)
        searchHistoryStore.updateAuthenticatedUser(user)
    }
}
