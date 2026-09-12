import Foundation

enum CommunityUsernameRules {
    static let minimumLength = 3
    static let maximumLength = 30

    static let reservedNames: Set<String> = [
        "about", "admin", "api", "app", "auth", "community", "discover",
        "explore", "feed", "groups", "help", "home", "login", "messages",
        "norge360", "notifications", "plan", "privacy", "profile", "search",
        "settings", "signup", "support", "terms", "user", "users", "www",
    ]

    static func normalized(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.count >= minimumLength, candidate.count <= maximumLength else { return nil }
        guard candidate.range(of: "^[a-z0-9](?:[a-z0-9_]{1,28}[a-z0-9])?$", options: .regularExpression) != nil else {
            return nil
        }
        guard !reservedNames.contains(candidate) else { return nil }
        return candidate
    }
}
