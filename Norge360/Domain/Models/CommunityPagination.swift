import Foundation

struct CommunityPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?

    var hasMore: Bool { nextCursor != nil }
}

struct CommunityMessagePage<Item: Sendable>: Sendable {
    let items: [Item]
    let hasMoreOlder: Bool
}

enum CommunityPaginationError: Error, Equatable {
    case invalidCursor
}

struct CommunityKeysetCursor: Codable, Sendable, Equatable {
    let value: String
    let id: UUID

    init(value: String, id: UUID) {
        self.value = value
        self.id = id
    }

    init(encoded: String) throws {
        guard
            encoded.count <= 512,
            let data = Data(base64Encoded: encoded),
            let cursor = try? JSONDecoder().decode(Self.self, from: data),
            !cursor.value.isEmpty
        else {
            throw CommunityPaginationError.invalidCursor
        }
        self = cursor
    }

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }
}
