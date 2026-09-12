import Foundation

enum CommunityGroupRules {
    static let reservedSlugs: Set<String> = CommunityUsernameRules.reservedNames.union([
        "create", "edit", "events", "manage", "members", "new",
    ])

    static func normalizedSlug(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.count >= 3, candidate.count <= 50 else { return nil }
        guard candidate.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return nil }
        guard !reservedSlugs.contains(candidate) else { return nil }
        return candidate
    }

    static func isValid(name: String, slug: String, description: String) -> Bool {
        (3...100).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && normalizedSlug(slug) != nil
            && (10...500).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
}
