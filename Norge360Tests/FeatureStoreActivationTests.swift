import XCTest

@testable import Norge360

@MainActor
final class FeatureStoreActivationTests: XCTestCase {
    func testEventsStayIdleUntilTheirSurfaceActivates() async {
        let counter = CallCounter()
        let store = CommunityEventsStore(service: EventActivationFixture(counter: counter))
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))

        await Task.yield()
        let countBeforeActivation = await counter.get()
        XCTAssertEqual(countBeforeActivation, 0)

        await store.activate()
        let countAfterActivation = await counter.get()
        XCTAssertEqual(countAfterActivation, 1)

        await store.activate()
        let countAfterSecondActivation = await counter.get()
        XCTAssertEqual(countAfterSecondActivation, 1)
    }

    func testConcurrentEventReloadsShareOneInFlightRequest() async {
        let counter = CallCounter()
        let store = CommunityEventsStore(service: DelayedEventFixture(counter: counter))
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))

        let firstReload = Task { await store.reload() }
        try? await Task.sleep(for: .milliseconds(10))
        let secondReload = Task { await store.reload() }
        await firstReload.value
        await secondReload.value

        let requestCount = await counter.get()
        XCTAssertEqual(requestCount, 1)
    }

    func testNotificationsStayIdleUntilTheirSurfaceActivates() async {
        let counter = CallCounter()
        let store = CommunityNotificationsStore(service: NotificationActivationFixture(counter: counter))
        store.updateAuthenticatedUser(AuthenticatedUser(id: UUID(), email: nil))

        await Task.yield()
        let countBeforeActivation = await counter.get()
        XCTAssertEqual(countBeforeActivation, 0)

        await store.activate()
        let countAfterActivation = await counter.get()
        XCTAssertEqual(countAfterActivation, 1)
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() { value += 1 }

    func get() -> Int { value }
}

private struct EventActivationFixture: CommunityEventsProviding {
    let counter: CallCounter

    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    > {
        await counter.increment()
        return CommunityPage(items: [], nextCursor: nil)
    }

    func create(draft: CommunityEventDraft) async throws -> CommunityEvent { fatalError("unused") }

    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws {}

    func setLiked(eventID: UUID, isLiked: Bool) async throws {}

    func invite(eventID: UUID, userID: UUID) async throws {}

    func delete(eventID: UUID) async throws {}
}

private struct DelayedEventFixture: CommunityEventsProviding {
    let counter: CallCounter

    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    > {
        await counter.increment()
        try await Task.sleep(for: .milliseconds(50))
        return CommunityPage(items: [], nextCursor: nil)
    }

    func create(draft: CommunityEventDraft) async throws -> CommunityEvent { fatalError("unused") }

    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws {}

    func setLiked(eventID: UUID, isLiked: Bool) async throws {}

    func invite(eventID: UUID, userID: UUID) async throws {}

    func delete(eventID: UUID) async throws {}
}

private struct NotificationActivationFixture: CommunityNotificationsProviding {
    let counter: CallCounter

    func loadNotifications() async throws -> [CommunityNotificationItem] {
        await counter.increment()
        return []
    }

    func notificationEvents(for recipientID: UUID) async -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }

    func markRead(id: UUID) async throws {}

    func markAllRead() async throws {}

    func delete(id: UUID) async throws {}
}
