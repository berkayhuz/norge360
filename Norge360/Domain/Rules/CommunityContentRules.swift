import Foundation

enum CommunityContentRules {
    static let maximumPostLength = 1_024
    static let maximumPostTitleLength = 220
    static let maximumCommentLength = 1_024
    static let maximumDisplayNameLength = 80
    static let maximumBiographyLength = 160
    static let maximumCityOrRegionLength = 120
    static let maximumPostImageCount = 6
    static let postEditHistoryDelay: TimeInterval = 120

    static func normalizedPostBody(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximumPostLength else { return nil }
        return trimmed
    }

    static func normalizedPostTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximumPostTitleLength else { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedBiography(_ biography: String) -> String? {
        let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maximumBiographyLength else { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedCommentBody(_ body: String) -> String? {
        normalized(body, maximumLength: maximumCommentLength)
    }

    static func normalizedDisplayName(_ name: String) -> String? {
        normalized(name, maximumLength: maximumDisplayNameLength)
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
