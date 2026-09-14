import XCTest

@testable import Norge360

final class SupabaseClientFactoryTests: XCTestCase {
    func testNetworkSessionFailsFastAndDoesNotWaitForConnectivity() {
        let session = SupabaseClientFactory.makeNetworkSession()

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 90)
        XCTAssertFalse(session.configuration.waitsForConnectivity)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }
}
