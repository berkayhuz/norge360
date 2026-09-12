import Foundation

enum CommunityHashtagRules {
    static let maximumLength = 50

    static func activePrefix(in text: String) -> String? {
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).last,
            token.first == "#"
        else {
            return nil
        }

        let prefix = String(token.dropFirst()).lowercased()
        guard !prefix.isEmpty,
            prefix.count <= maximumLength,
            prefix.unicodeScalars.allSatisfy(isAllowed)
        else {
            return nil
        }
        return prefix
    }

    static func replacingActiveHashtag(in text: String, with tag: String) -> String {
        guard let prefix = activePrefix(in: text), !prefix.isEmpty else { return text }
        guard let range = text.range(of: "#\(prefix)", options: [.backwards, .caseInsensitive]) else { return text }
        return text.replacingCharacters(in: range, with: "#\(tag) ")
    }

    static func searchTag(from query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.first == "#" else { return nil }
        let tag = String(value.dropFirst()).lowercased()
        guard !tag.isEmpty,
            tag.count <= maximumLength,
            tag.unicodeScalars.allSatisfy(isAllowed)
        else {
            return nil
        }
        return tag
    }

    private static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
}
