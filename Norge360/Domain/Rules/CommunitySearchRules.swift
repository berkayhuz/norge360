import Foundation

enum CommunitySearchRules {
    static let minimumLength = 3
    static let maximumLength = 80

    static func normalizedQuery(_ value: String) -> String? {
        let collapsed =
            value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count >= minimumLength, collapsed.count <= maximumLength else {
            return nil
        }
        return collapsed
    }
}
