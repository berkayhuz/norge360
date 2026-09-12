import XCTest

@testable import Norge360

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private let suiteName = "AppearanceSettingsTests"
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToSystemAppearance() {
        XCTAssertEqual(AppearanceSettings(defaults: defaults).appearance, .system)
    }

    func testPersistsSelectedAppearance() {
        let settings = AppearanceSettings(defaults: defaults)
        settings.appearance = .dark

        XCTAssertEqual(AppearanceSettings(defaults: defaults).appearance, .dark)
    }
}
