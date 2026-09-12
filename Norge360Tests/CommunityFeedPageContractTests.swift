import XCTest

@testable import Norge360

final class CommunityFeedPageContractTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testFeedPageRPCRowDecodesAggregatesAndNestedPublicData() throws {
        let data = Data(
            #"""
            {
              "post": {
                "id": "11111111-1111-1111-1111-111111111111",
                "author_id": "22222222-2222-2222-2222-222222222222",
                "group_id": null,
                "body": "A practical community update.",
                "title": "A title",
                "kind": "update",
                "created_at": "2026-09-11T00:00:00Z",
                "updated_at": "2026-09-11T00:00:00Z"
              },
              "author": {
                "user_id": "22222222-2222-2222-2222-222222222222",
                "display_name": "Member",
                "username": "member",
                "preferred_locale": "en",
                "public_languages": ["en"],
                "interests": ["newcomers"],
                "is_public": true,
                "avatar_path": "22222222-2222-2222-2222-222222222222/avatar.jpg",
                "created_at": "2026-09-11T00:00:00Z",
                "updated_at": "2026-09-11T00:00:00Z"
              },
              "media": [
                {
                  "id": "33333333-3333-3333-3333-333333333333",
                  "post_id": "11111111-1111-1111-1111-111111111111",
                  "storage_path": "22222222-2222-2222-2222-222222222222/post.jpg",
                  "sort_order": 0,
                  "width": 1200,
                  "height": 800,
                  "created_at": "2026-09-11T00:00:00Z"
                }
              ],
              "likes_count": 42,
              "is_liked_by_current_user": true,
              "comments_count": 7,
              "edit_history_count": 1
            }
            """#.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(CommunityFeedPageRow.self, from: data)

        XCTAssertEqual(row.post.id.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(row.author.username, "member")
        XCTAssertEqual(row.media.count, 1)
        XCTAssertEqual(row.likesCount, 42)
        XCTAssertTrue(row.isLikedByCurrentUser)
        XCTAssertEqual(row.commentsCount, 7)
        XCTAssertEqual(row.editHistoryCount, 1)
    }

    func testPostCommentRPCRowDecodesCommentAndPublicAuthor() throws {
        let data = Data(
            #"""
            {
              "comment": {
                "id": "11111111-1111-1111-1111-111111111111",
                "post_id": "22222222-2222-2222-2222-222222222222",
                "author_id": "33333333-3333-3333-3333-333333333333",
                "body": "A useful reply.",
                "created_at": "2026-09-11T00:00:00Z",
                "updated_at": "2026-09-11T00:00:00Z"
              },
              "author": {
                "user_id": "33333333-3333-3333-3333-333333333333",
                "display_name": "Member",
                "username": "member",
                "preferred_locale": "en",
                "public_languages": ["en"],
                "interests": ["newcomers"],
                "is_public": true,
                "avatar_path": "33333333-3333-3333-3333-333333333333/avatar.jpg",
                "created_at": "2026-09-11T00:00:00Z",
                "updated_at": "2026-09-11T00:00:00Z"
              }
            }
            """#.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(CommunityPostCommentRow.self, from: data)

        XCTAssertEqual(row.comment.body, "A useful reply.")
        XCTAssertEqual(row.comment.authorID, row.author.userID)
        XCTAssertEqual(row.author.avatarPath, "33333333-3333-3333-3333-333333333333/avatar.jpg")
    }

    func testPostCounterRPCRowDecodesAggregatesAndCurrentUserState() throws {
        let data = Data(
            #"""
            {
              "post_id": "11111111-1111-1111-1111-111111111111",
              "likes_count": 42,
              "is_liked_by_current_user": true,
              "comments_count": 7,
              "edit_history_count": 1
            }
            """#.utf8
        )

        let row = try JSONDecoder().decode(CommunityPostCounterRow.self, from: data)

        XCTAssertEqual(row.postID.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(row.likesCount, 42)
        XCTAssertTrue(row.isLikedByCurrentUser)
        XCTAssertEqual(row.commentsCount, 7)
        XCTAssertEqual(row.editHistoryCount, 1)
    }

    func testEventCounterRPCRowDecodesAggregateAndCurrentUserState() throws {
        let data = Data(
            #"""
            {
              "event_id": "11111111-1111-1111-1111-111111111111",
              "likes_count": 12,
              "is_liked_by_current_user": false
            }
            """#.utf8
        )

        let row = try JSONDecoder().decode(CommunityEventCounterRow.self, from: data)

        XCTAssertEqual(row.eventID.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(row.likesCount, 12)
        XCTAssertFalse(row.isLikedByCurrentUser)
    }
}
