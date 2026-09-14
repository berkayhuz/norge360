import XCTest

@testable import Norge360

final class UserFacingErrorTests: XCTestCase {
    private struct BackendError: Error {
        let message: String
    }

    func testBackendDetailsAreNotReturnedToTheUser() {
        let error = BackendError(message: "database constraint details")

        let message = UserFacingErrorMapper.message(
            for: error,
            fallbackKey: "feed.error",
            operation: "test.operation"
        )

        XCTAssertEqual(message, AppStrings.localized("feed.error"))
        XCTAssertFalse(message.contains(error.message))
        XCTAssertFalse(message.contains("BackendError"))
    }
}
