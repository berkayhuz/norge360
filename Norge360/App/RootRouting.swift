import Foundation

enum RootRoute: Equatable {
    case loading
    case getStarted
    case accountSetup
    case home
    case authentication
}

enum RootRouting {
    static func route(
        isAuthenticationLoading: Bool,
        isAuthenticated: Bool,
        isAccountSetupLoading: Bool,
        requiresAccountSetup: Bool
    ) -> RootRoute {
        if isAuthenticationLoading {
            return .loading
        }

        if isAuthenticated {
            if isAccountSetupLoading {
                return .loading
            }
            return requiresAccountSetup ? .accountSetup : .home
        }

        return .getStarted
    }
}
