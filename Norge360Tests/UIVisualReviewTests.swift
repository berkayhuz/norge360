// TEMPORARY review fixture. Remove after collecting UI screenshots.
import SwiftUI
import UIKit
import XCTest

@testable import Norge360

@MainActor
final class UIVisualReviewTests: XCTestCase {
    // This fixture deliberately renders every core destination in one pass.
    // swiftlint:disable:next function_body_length
    func testRenderCommunityScreens() async throws {
        let feed = CommunityFeedStore(service: QAFeed())
        let groups = CommunityGroupsStore(service: QAGroups())
        let auth = AuthenticationStore(service: QAAuth())
        let notifications = CommunityNotificationsStore(service: QANotifications())
        let events = CommunityEventsStore(service: QAEvents())
        let conversations = CommunityConversationsStore(service: QAConversations())
        let search = CommunitySearchStore(service: QASearch())
        let profile = CommunityProfileStore(service: QAProfile())
        let follows = CommunityFollowStore(service: QAFollows())
        let tabRouter = AppTabRouter()
        await feed.reload()
        await conversations.reload()
        let screens: [(String, AnyView)] = [
            ("home", AnyView(CommunityFeedView())),
            ("explore", AnyView(ExploreView())),
            (
                "profile",
                AnyView(
                    NavigationStack { CommunityMemberProfileView(userID: QAFixture.memberID) })
            ),
            ("messages", AnyView(CommunityConversationsView())),
            (
                "conversation",
                AnyView(NavigationStack { CommunityConversationDetailView(conversation: QAFixture.conversation) })
            ),
            ("post", AnyView(NavigationStack { CommunityPostDetailView(item: QAFixture.posts[0]) })),
            ("comments", AnyView(NavigationStack { CommunityPostCommentsView(item: QAFixture.posts[0]) })),
            (
                "image_editor",
                AnyView(
                    CommunityImageEditor(
                        source: CommunityImageDraft(data: try makePhoto(), aspect: .square), onConfirm: { _ in }))
            ),
        ]
        for (variant, size, scheme, type) in [
            ("dark", CGSize(width: 390, height: 844), ColorScheme.dark, DynamicTypeSize.large),
            ("light", CGSize(width: 390, height: 844), ColorScheme.light, DynamicTypeSize.large),
            ("small_ax", CGSize(width: 320, height: 667), ColorScheme.dark, DynamicTypeSize.accessibility2),
        ] {
            for (name, screen) in screens {
                let view =
                    screen
                    .environmentObject(feed).environmentObject(groups).environmentObject(auth)
                    .environmentObject(notifications).environmentObject(conversations)
                    .environmentObject(search).environmentObject(profile).environmentObject(follows)
                    .environmentObject(events)
                    .environmentObject(tabRouter)
                    .environment(\.dynamicTypeSize, type)
                    .environment(\.colorScheme, scheme)
                    .preferredColorScheme(scheme)
                try await render(view, name: "\(name)_\(variant)", size: size, scheme: scheme)
            }
        }
    }

    private func render<V: View>(_ view: V, name: String, size: CGSize, scheme: ColorScheme) async throws {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("norge360-ui-qa")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"))
        print("UI_QA_IMAGE \(folder.appendingPathComponent(name + ".png").path)")
    }

    private func makePhoto() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor(red: 0.25, green: 0.54, blue: 0.65, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            UIColor(red: 0.12, green: 0.35, blue: 0.34, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 420, width: 600, height: 480))
            UIColor(red: 0.93, green: 0.76, blue: 0.39, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 220, y: 200, width: 160, height: 160))
        }
        return try XCTUnwrap(image.pngData())
    }
}

private enum QAFixture {
    private static func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else { fatalError("Invalid QA fixture UUID: \(value)") }
        return uuid
    }

    static let userID = uuid("00000000-0000-0000-0000-000000000001")
    static let memberID = uuid("00000000-0000-0000-0000-000000000002")
    static let conversationID = uuid("00000000-0000-0000-0000-000000000003")
    static let user = AuthenticatedUser(id: userID, email: nil)
    static let member = CommunityProfile(
        userID: memberID, displayName: "Sofia Berg", username: "sofiaberg", preferredLocale: "en",
        norwayStatus: .resident, cityOrRegion: "Oslo", publicLanguages: ["en", "nb"],
        interests: ["newcomers", "travel"], isPublic: true, avatarPath: nil, coverPath: nil, createdAt: .now,
        updatedAt: .now)
    static let posts = [
        CommunityFeedItem(
            post: CommunityPost(
                id: UUID(), authorID: memberID,
                body:
                    "A little Oslo sunshine and a new favourite walk along the river. 🌿\n\n"
                    + "Does anyone have a quiet café recommendation around Grünerløkka?",
                kind: .question, createdAt: .now.addingTimeInterval(-600), updatedAt: .now), author: member, media: [],
            likesCount: 24, isLikedByCurrentUser: false, commentsCount: 8, editHistoryCount: 0),
        CommunityFeedItem(
            post: CommunityPost(
                id: UUID(), authorID: memberID,
                body:
                    "Welcome to everyone settling into Norway this week! "
                    + "Share one thing that made your first days easier.",
                kind: .update, createdAt: .now.addingTimeInterval(-3600), updatedAt: .now), author: member, media: [],
            likesCount: 12, isLikedByCurrentUser: true, commentsCount: 4, editHistoryCount: 1),
    ]
    static let conversation = CommunityConversationSummary(
        conversationID: conversationID, status: .active, requestedByID: userID, createdAt: .now,
        updatedAt: .now.addingTimeInterval(-120), otherUserID: memberID, displayName: "Sofia Berg",
        username: "sofiaberg", avatarPath: nil, avatarURL: nil, lastMessage: nil)
    static let conversations = [
        conversation,
        CommunityConversationSummary(
            conversationID: UUID(), status: .active, requestedByID: userID, createdAt: .now,
            updatedAt: .now.addingTimeInterval(-2400), otherUserID: UUID(), displayName: "Emre Yılmaz",
            username: "emreyilmaz", avatarPath: nil, avatarURL: nil, lastMessage: nil),
    ]
    static let messages = [
        CommunityMessage(
            id: UUID(), conversationID: conversationID, senderID: memberID, body: "Hei! Welcome to Oslo 👋",
            createdAt: .now.addingTimeInterval(-1000), deletedAt: nil),
        CommunityMessage(
            id: UUID(), conversationID: conversationID, senderID: userID,
            body: "Thank you! Really looking forward to meeting people and exploring the city.",
            createdAt: .now.addingTimeInterval(-900), deletedAt: nil),
        CommunityMessage(
            id: UUID(), conversationID: conversationID, senderID: memberID,
            body: "There's a lovely walk along Akerselva. We could meet by the park this weekend if you're free.",
            createdAt: .now.addingTimeInterval(-700), deletedAt: nil),
        CommunityMessage(
            id: UUID(), conversationID: conversationID, senderID: userID,
            body: "That sounds great! Saturday afternoon works for me.", createdAt: .now.addingTimeInterval(-500),
            deletedAt: nil),
    ]
    static var comments: [CommunityCommentItem] {
        [
            CommunityCommentItem(
                comment: CommunityComment(
                    id: UUID(), postID: posts[0].id, authorID: memberID,
                    body: "The river walk is beautiful this time of year!", createdAt: .now.addingTimeInterval(-400),
                    updatedAt: .now), author: member)
        ]
    }
}
private enum QAError: Error { case unexpectedMutation }

private struct QAAuth: AuthProviding {
    func signIn(email: String, password: String) async throws -> AuthenticatedUser { QAFixture.user }
    func signIn(with provider: SocialAuthProvider) async throws -> AuthenticatedUser { QAFixture.user }
    func signUp(email: String, password: String) async throws -> SignUpResult { .authenticated(QAFixture.user) }
    func resendConfirmation(email: String) async throws { throw QAError.unexpectedMutation }
    func sendPasswordReset(email: String) async throws { throw QAError.unexpectedMutation }
    func updatePassword(_ password: String) async throws { throw QAError.unexpectedMutation }
    func updateEmail(_ email: String) async throws { throw QAError.unexpectedMutation }
    func signOut() async throws { throw QAError.unexpectedMutation }
    func handleCallbackURL(_ url: URL) {}
    func lifecycleEvents() -> AsyncStream<AuthLifecycleEvent> {
        AsyncStream {
            $0.yield(.sessionChanged(QAFixture.user))
            $0.finish()
        }
    }
}

private struct QAFeed: CommunityFeedProviding {
    func loadFeedPage(cursor: String?, limit: Int) async throws -> CommunityPage<CommunityFeedItem> {
        CommunityPage(items: QAFixture.posts, nextCursor: nil)
    }
    func loadMemberProfile(userID: UUID) async throws -> CommunityProfile? { QAFixture.member }
    func loadMemberPosts(userID: UUID) async throws -> [CommunityFeedItem] { QAFixture.posts }
    func loadMemberReplies(userID: UUID) async throws -> [CommunityFeedItem] { QAFixture.posts }
    func loadMemberMedia(userID: UUID) async throws -> [CommunityFeedItem] { QAFixture.posts }
    func loadLikedPosts(userID: UUID) async throws -> [CommunityFeedItem] { QAFixture.posts }
    func loadMemberStats(userID: UUID) async throws -> CommunityMemberProfileStats? {
        CommunityMemberProfileStats(userID: QAFixture.memberID, postsCount: 12, likesCount: 184, commentsCount: 36)
    }
    func loadPosts(ids: [UUID]) async throws -> [CommunityFeedItem] { QAFixture.posts.filter { ids.contains($0.id) } }
    func loadPost(id: UUID) async throws -> CommunityFeedItem? { QAFixture.posts.first { $0.id == id } }
    func searchHashtags(prefix: String) async throws -> [CommunityHashtagSuggestion] { [] }
    func loadHashtagPosts(tag: String) async throws -> [CommunityFeedItem] { [] }
    func loadGroupPosts(groupID: UUID) async throws -> [CommunityFeedItem] { [] }
    func createPost(title: String, body: String, kind: CommunityPostKind, groupID: UUID?, media: [CommunityImageUpload])
        async throws
    { throw QAError.unexpectedMutation }
    func updatePost(id: UUID, body: String) async throws { throw QAError.unexpectedMutation }
    func deletePost(id: UUID) async throws { throw QAError.unexpectedMutation }
    func removeGroupPost(id: UUID, groupID: UUID) async throws { throw QAError.unexpectedMutation }
    func toggleLike(postID: UUID) async throws -> Bool { false }
    func loadComments(postID: UUID) async throws -> [CommunityCommentItem] { QAFixture.comments }
    func createComment(postID: UUID, body: String) async throws { throw QAError.unexpectedMutation }
    func updateComment(id: UUID, body: String) async throws { throw QAError.unexpectedMutation }
    func deleteComment(id: UUID) async throws { throw QAError.unexpectedMutation }
    func loadPostEditHistory(postID: UUID) async throws -> [CommunityPostEditHistory] { [] }
    func reportPost(id: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func reportComment(id: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func reportEvent(id: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func reportProfile(id: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func reportGroup(id: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func blockUser(id: UUID) async throws { throw QAError.unexpectedMutation }
    func loadBlockedMembers() async throws -> [CommunityBlockedMember] { [] }
    func unblockUser(id: UUID) async throws { throw QAError.unexpectedMutation }
}

private struct QAGroups: CommunityGroupsProviding {
    func loadGroups(cursor: String?, limit: Int, searchQuery: String?) async throws -> CommunityPage<CommunityGroup> {
        CommunityPage(items: [], nextCursor: nil)
    }
    func loadGroups(groupIDs: [UUID]) async throws -> [CommunityGroup] { [] }
    func loadMemberships() async throws -> [CommunityGroupMembership] { [] }
    func loadMyJoinRequestStates() async throws -> [CommunityGroupJoinRequestState] { [] }
    func requestJoin(groupID: UUID) async throws -> CommunityGroupJoinResult { throw QAError.unexpectedMutation }
    func cancelJoinRequest(groupID: UUID) async throws { throw QAError.unexpectedMutation }
    func leave(groupID: UUID) async throws { throw QAError.unexpectedMutation }
    func create(draft: CommunityGroupDraft) async throws -> CommunityGroup { throw QAError.unexpectedMutation }
    func updateDetails(groupID: UUID, draft: CommunityGroupDetailsDraft) async throws -> CommunityGroup {
        throw QAError.unexpectedMutation
    }
    func loadMembers(groupID: UUID) async throws -> [CommunityGroupMembership] { [] }
    func manageMember(groupID: UUID, userID: UUID, action: String, role: String?) async throws {
        throw QAError.unexpectedMutation
    }
    func transferOwnership(groupID: UUID, userID: UUID) async throws { throw QAError.unexpectedMutation }
    func loadMemberProfiles(userIDs: [UUID]) async throws -> [CommunityProfile] { [] }
    func updatePostingPermission(groupID: UUID, permission: CommunityGroupPostingPermission) async throws {
        throw QAError.unexpectedMutation
    }
    func updateVisibility(groupID: UUID, visibility: CommunityGroupVisibility) async throws {
        throw QAError.unexpectedMutation
    }
    func loadJoinRequests(groupID: UUID) async throws -> [CommunityGroupJoinRequest] { [] }
    func reviewJoinRequest(groupID: UUID, userID: UUID, decision: String) async throws {
        throw QAError.unexpectedMutation
    }
    func loadBans(groupID: UUID) async throws -> [CommunityGroupBan] { [] }
    func banMember(groupID: UUID, userID: UUID) async throws { throw QAError.unexpectedMutation }
    func unbanMember(groupID: UUID, userID: UUID) async throws { throw QAError.unexpectedMutation }
    func inviteMember(groupID: UUID, userID: UUID) async throws { throw QAError.unexpectedMutation }
    func updatePhoto(groupID: UUID, image: CommunityImageUpload) async throws -> CommunityGroup {
        throw QAError.unexpectedMutation
    }
}

private struct QANotifications: CommunityNotificationsProviding {
    func loadNotifications() async throws -> [CommunityNotificationItem] { [] }
    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func markRead(id: UUID) async throws { throw QAError.unexpectedMutation }
    func markAllRead() async throws { throw QAError.unexpectedMutation }
    func delete(id: UUID) async throws { throw QAError.unexpectedMutation }
}

private struct QAConversations: CommunityConversationsProviding {
    func loadConversations() async throws -> [CommunityConversationSummary] { QAFixture.conversations }
    func createRequest(to userID: UUID) async throws -> UUID { throw QAError.unexpectedMutation }
    func respond(conversationID: UUID, accept: Bool) async throws { throw QAError.unexpectedMutation }
    func loadMessages(conversationID: UUID) async throws -> [CommunityMessage] { QAFixture.messages }
    func loadMessages(
        conversationID: UUID, after cursor: CommunityMessageCursor
    ) async throws -> [CommunityMessage] { [] }
    func send(conversationID: UUID, body: String) async throws -> UUID { throw QAError.unexpectedMutation }
    func send(conversationID: UUID, body: String, attachmentID: UUID) async throws -> UUID {
        throw QAError.unexpectedMutation
    }
    func stageImage(conversationID: UUID, jpegData: Data) async throws -> UUID { throw QAError.unexpectedMutation }
    func imageURL(attachmentID: UUID) async throws -> URL { throw QAError.unexpectedMutation }
    func cancelImage(attachmentID: UUID) async throws { throw QAError.unexpectedMutation }
    func markRead(conversationID: UUID) async throws { () }
    func messageEvents(conversationID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func conversationEvents(for recipientID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func readReceipt(conversationID: UUID) async throws -> CommunityMessageReadReceipt? { nil }
    func readReceiptsEnabled() async throws -> Bool { false }
    func updateReadReceipts(enabled: Bool) async throws { throw QAError.unexpectedMutation }
    func hide(messageID: UUID) async throws { throw QAError.unexpectedMutation }
    func report(messageID: UUID, reason: CommunityReportReason) async throws { throw QAError.unexpectedMutation }
    func loadSettings() async throws -> [CommunityConversationSettings] { [] }
    func updateSettings(_ settings: CommunityConversationSettings) async throws { throw QAError.unexpectedMutation }
}

private struct QAProfile: CommunityProfileProviding {
    func loadProfile() async throws -> CommunityProfile? { QAFixture.member }
    func isUsernameAvailable(_ username: String) async throws -> Bool { false }
    func saveProfile(_ draft: CommunityProfileDraft) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
    func updateAvatar(with image: CommunityImageUpload) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
    func updateCover(with image: CommunityImageUpload) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
    func updateVisibility(isPublic: Bool) async throws -> CommunityProfile { throw QAError.unexpectedMutation }
    func updateFieldVisibility(showNorwayStatus: Bool, showLocation: Bool) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
    func updatePreferredLanguage(_ language: AppLanguage) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
    func updateDetails(_ draft: CommunityProfileDraft) async throws -> CommunityProfile {
        throw QAError.unexpectedMutation
    }
}

private struct QAFollows: CommunityFollowProviding {
    func loadState(for userID: UUID) async throws -> CommunityFollowState {
        CommunityFollowState(isFollowing: false, followersCount: 128, followingCount: 76)
    }
    func toggleFollow(for userID: UUID) async throws -> Bool { false }
    func loadProfiles(for userID: UUID, relationship: CommunityFollowListKind) async throws -> [CommunityProfile] {
        [QAFixture.member]
    }
    func loadVisibility() async throws -> CommunityFollowVisibilitySettings { CommunityFollowVisibilitySettings() }
    func updateVisibility(_ settings: CommunityFollowVisibilitySettings) async throws {}
    func loadLikedPostsVisibility() async throws -> CommunityLikedPostsVisibility { .onlyMe }
    func updateLikedPostsVisibility(_ visibility: CommunityLikedPostsVisibility) async throws {}
}

private struct QAEvents: CommunityEventsProviding {
    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    > {
        CommunityPage(items: [], nextCursor: nil)
    }
    func create(draft: CommunityEventDraft) async throws -> CommunityEvent { throw QAError.unexpectedMutation }
    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws { throw QAError.unexpectedMutation }
    func setLiked(eventID: UUID, isLiked: Bool) async throws { throw QAError.unexpectedMutation }
    func invite(eventID: UUID, userID: UUID) async throws { throw QAError.unexpectedMutation }
    func delete(eventID: UUID) async throws { throw QAError.unexpectedMutation }
}

private struct QASearch: CommunitySearchProviding {
    func search(query: String) async throws -> CommunitySearchResults {
        CommunitySearchResults(profiles: [QAFixture.member], groups: [], posts: QAFixture.posts.map(\.post))
    }
}
