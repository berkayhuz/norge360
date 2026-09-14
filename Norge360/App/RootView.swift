import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var accountSetupStore: AccountSetupStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var feedStore: CommunityFeedStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    @EnvironmentObject private var searchStore: CommunitySearchStore
    @EnvironmentObject private var notificationsStore: CommunityNotificationsStore
    @EnvironmentObject private var groupChatStore: CommunityGroupChatStore
    @State private var toastItem: CommunityNotificationItem?
    @State private var toastDestination: CommunityNotificationItem?
    @StateObject private var toastDismissDebouncer = NorgeTaskDebouncer()
    @State private var groupToastSignal: CommunityGroupChatIncomingSignal?
    @State private var groupToastDestination: CommunityGroupChatIncomingSignal?
    @StateObject private var feedbackToastCenter = NorgeToastCenter.shared
    @State private var hasCompletedCurrentLaunch = false
    #if DEBUG
        @State private var isShowingDebugPanel = false
        @State private var debugDestination: DebugPreviewDestination?
    #endif

    var body: some View {
        ZStack {
            Color.norgeAppBackground
                .ignoresSafeArea(.container, edges: .top)

            if hasCompletedCurrentLaunch || authenticationStore.isLoading {
                switch RootRouting.route(
                    isAuthenticationLoading: authenticationStore.isLoading,
                    isAuthenticated: authenticationStore.isAuthenticated,
                    isAccountSetupLoading: accountSetupStore.isLoading || communityProfileStore.isLoading,
                    requiresAccountSetup: accountSetupStore.requiresSetup || communityProfileStore.requiresSetup
                ) {
                case .loading:
                    NorgeLoadingState(fillsAvailableSpace: true)
                case .getStarted:
                    GetStartedView()
                case .accountSetup:
                    AccountSetupFlowView()
                case .home:
                    AuthenticatedHomeView()
                case .authentication:
                    AuthFlowView()
                }
            } else {
                LaunchView {
                    hasCompletedCurrentLaunch = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardDismissBridge())
        .overlay(alignment: .top) {
            if let toastItem {
                Button {
                    openToast(toastItem)
                } label: {
                    CommunityNotificationToast(item: toastItem)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: 620)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.height < -24 {
                                dismissToast(id: toastItem.id)
                            }
                        }
                )
                .accessibilityHint(AppStrings.localized("notifications.open_hint"))
            } else if let groupToastSignal {
                Button {
                    openGroupToast(groupToastSignal)
                } label: {
                    CommunityGroupChatToast()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: 620)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityHint(AppStrings.localized("notifications.open_hint"))
            } else if let feedbackToast = feedbackToastCenter.current {
                NorgeFeedbackToast(item: feedbackToast)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: 620)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                if value.translation.height < -24 {
                                    feedbackToastCenter.dismiss(id: feedbackToast.id)
                                }
                            }
                    )
            }
        }
        .animation(.snappy(duration: 0.28), value: toastItem?.id)
        .animation(.snappy(duration: 0.28), value: feedbackToastCenter.current?.id)
        .onChange(of: notificationsStore.incomingNotification) { _, item in
            guard let item else { return }
            presentToast(item)
        }
        .onChange(of: groupChatStore.incomingSignal) { _, signal in
            guard let signal else { return }
            presentGroupToast(signal)
        }
        .onChange(of: authenticationStore.isAuthenticated) { wasAuthenticated, isAuthenticated in
            // A sign-out begins a new session, so show Launch and then the
            // signed-out Get Started entry point again.
            if wasAuthenticated && !isAuthenticated {
                hasCompletedCurrentLaunch = false
            }
        }
        .onChange(of: communityProfileStore.profile) { _, profile in
            if let profile {
                feedStore.applyUpdatedProfile(profile)
                conversationsStore.applyUpdatedProfile(profile)
                searchStore.applyUpdatedProfile(profile)
                notificationsStore.applyUpdatedProfile(profile)
            }
        }
        .sheet(item: $toastDestination) { item in
            NavigationStack {
                CommunityNotificationDestinationView(item: item)
            }
        }
        .sheet(item: $groupToastDestination) { signal in
            NavigationStack {
                CommunityGroupChatSignalDestinationView(signal: signal)
            }
        }
        .onDisappear { toastDismissDebouncer.cancel() }
        .fullScreenCover(isPresented: $authenticationStore.needsPasswordUpdate) {
            NavigationStack { ResetPasswordView() }
        }
        #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isShowingDebugPanel = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.norgePrimary, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 24)
                .accessibilityLabel(AppStrings.localized("debug.open_ui_preview"))
            }
            .sheet(isPresented: $isShowingDebugPanel) {
                DebugPreviewPanel { destination in
                    isShowingDebugPanel = false
                    debugDestination = destination
                }
                .presentationDetents([.medium])
            }
            .fullScreenCover(item: $debugDestination) { destination in
                DebugPreviewHost(destination: destination) {
                    debugDestination = nil
                }
            }
        #endif
    }

    private func presentToast(_ item: CommunityNotificationItem) {
        toastDismissDebouncer.cancel()
        withAnimation { toastItem = item }
        toastDismissDebouncer.schedule(after: .seconds(4)) {
            dismissToast(id: item.id)
        }
    }

    private func openToast(_ item: CommunityNotificationItem) {
        toastDismissDebouncer.cancel()
        toastDestination = item
        dismissToast(id: item.id)
    }

    private func dismissToast(id: UUID) {
        withAnimation { toastItem = nil }
        notificationsStore.clearIncomingNotification(id: id)
    }

    private func openGroupToast(_ signal: CommunityGroupChatIncomingSignal) {
        groupToastDestination = signal
        dismissGroupToast(id: signal.id)
    }

    private func presentGroupToast(_ signal: CommunityGroupChatIncomingSignal) {
        toastDismissDebouncer.cancel()
        withAnimation { groupToastSignal = signal }
        toastDismissDebouncer.schedule(after: .seconds(4)) {
            dismissGroupToast(id: signal.id)
        }
    }

    private func dismissGroupToast(id: UUID) {
        toastDismissDebouncer.cancel()
        withAnimation { groupToastSignal = nil }
        groupChatStore.clearIncomingSignal(id: id)
    }
}

private struct CommunityGroupChatToast: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(Color.norgePrimary)
                .frame(width: 42, height: 42)
                .background(Color.norgePrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.localized("groups.chat_new_message"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(AppStrings.localized("groups.chat_open_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Color.norgeTopBarBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 1) }
        .shadow(color: Color.norgeTopBarBackground.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}

private struct CommunityGroupChatSignalDestinationView: View {
    @EnvironmentObject private var groupsStore: CommunityGroupsStore
    let signal: CommunityGroupChatIncomingSignal
    @State private var group: CommunityGroup?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                NorgeLoadingState(fillsAvailableSpace: true)
            } else if let group {
                CommunityGroupChatView(group: group)
            } else {
                NorgeUnavailableState(
                    AppStrings.localized("notifications.group_unavailable_title"),
                    systemImage: "person.3",
                    description: AppStrings.localized("notifications.group_unavailable_body")
                )
            }
        }
        .task {
            await groupsStore.reload()
            if groupsStore.joinedGroupIDs.contains(signal.groupID) {
                group = groupsStore.groups.first(where: { $0.id == signal.groupID })
            }
            isLoading = false
        }
    }
}

private struct AuthenticatedHomeView: View {
    var body: some View {
        MainTabView()
    }
}
