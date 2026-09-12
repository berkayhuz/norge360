import XCTest

@testable import Norge360

final class AccountSetupContractTests: XCTestCase {
    func testAccountProfileDecodesOnlyRequiredPrivateFields() throws {
        let json = Data(
            """
            {
              "user_id": "00000000-0000-0000-0000-000000000001",
              "preferred_locale": "en"
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(AccountProfile.self, from: json)
        XCTAssertEqual(profile.preferredLocale, "en")
    }

    func testAccountProfileEncodesOnlyRequiredPrivateFields() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let profile = AccountProfile(
            userID: userID,
            preferredLocale: "en"
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]

        XCTAssertEqual(object?["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(object?["preferred_locale"] as? String, "en")
        XCTAssertNil(object?["full_name"])
        XCTAssertNil(object?["gender"])
        XCTAssertNil(object?["birth_date"])
    }
}
