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
    @Published var exploreScrollToTopToken = 0

    func openProfile(_ userID: UUID) {
        selectedTab = .profile
        profilePath = [userID]
    }

    func selectTab(_ tab: Tab) {
        let isExploreReselected = selectedTab == .explore && tab == .explore
        selectedTab = tab
        if isExploreReselected { exploreScrollToTopToken &+= 1 }
    }

}
