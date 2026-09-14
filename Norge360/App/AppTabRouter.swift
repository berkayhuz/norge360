import Foundation

/// A single source of truth for tab selection and profile deep links.  A member
/// profile is a product destination, not a child of whichever tab exposed it.
@MainActor
final class AppTabRouter: ObservableObject {
    enum Tab: Int, CaseIterable {
        case home, explore, messages, community, profile

        var localizationKey: String {
            switch self {
            case .home: "home"
            case .explore: "explore"
            case .messages: "messages"
            case .community: "community"
            case .profile: "profile"
            }
        }
    }

    @Published var selectedTab: Tab = .home
    @Published var profilePath: [UUID] = []
    @Published var isTabBarHidden = false
    /// Keeps the custom tab bar hidden while Settings is pushed on the
    /// profile navigation stack, including when the user changes tabs with a
    /// horizontal page gesture and later returns to Profile.
    @Published var isProfileSettingsFlowActive = false
    @Published var isHomeNotificationsFlowActive = false
    @Published var isCommunityLikedEventsFlowActive = false
    @Published var isTabBarCompact = false
    @Published var homeScrollToTopToken = 0
    @Published var exploreScrollToTopToken = 0
    @Published var messagesScrollToTopToken = 0
    @Published var communityScrollToTopToken = 0
    @Published var profileScrollToTopToken = 0

    func openProfile(_ userID: UUID) {
        selectedTab = .profile
        profilePath = [userID]
    }

    func selectTab(_ tab: Tab) {
        let isReselected = selectedTab == tab
        selectedTab = tab
        if tab != .profile {
            isTabBarHidden = false
        }
        isTabBarCompact = false
        guard isReselected else { return }

        switch tab {
        case .home:
            homeScrollToTopToken &+= 1
        case .explore:
            exploreScrollToTopToken &+= 1
        case .messages:
            messagesScrollToTopToken &+= 1
        case .community:
            communityScrollToTopToken &+= 1
        case .profile:
            profileScrollToTopToken &+= 1
        }
    }

    func setTabBarCompact(_ compact: Bool, for tab: Tab) {
        guard selectedTab == tab else { return }
        isTabBarCompact = compact
    }

}
