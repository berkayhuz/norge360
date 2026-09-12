import XCTest

@testable import Norge360

final class AppLanguageTests: XCTestCase {
    func testSupportedLanguageSetHasNorwegianFallbackAndSixteenLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 16)
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(LanguageSettings.detectedInitialLanguage(for: Locale(identifier: "xx-ZZ")), .norwegianBokmal)
        XCTAssertTrue(AppLanguage.allCases.contains(.dari))
        XCTAssertTrue(AppLanguage.allCases.contains(.tigrinya))
    }

    func testInitialLanguageFollowsSupportedDeviceRegion() {
        XCTAssertEqual(LanguageSettings.detectedInitialLanguage(for: Locale(identifier: "de-DE")), .german)
        XCTAssertEqual(LanguageSettings.detectedInitialLanguage(for: Locale(identifier: "tr-TR")), .turkish)
        XCTAssertEqual(LanguageSettings.detectedInitialLanguage(for: Locale(identifier: "nb-NO")), .norwegianBokmal)
    }

    func testRightToLeftLanguageSet() {
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertTrue(AppLanguage.persian.isRightToLeft)
        XCTAssertTrue(AppLanguage.dari.isRightToLeft)
        XCTAssertTrue(AppLanguage.urdu.isRightToLeft)
        XCTAssertFalse(AppLanguage.turkish.isRightToLeft)
    }

    @MainActor
    func testAccountLanguagePreferencePersistsTheSelectedLanguage() {
        let settings = LanguageSettings()
        let previousLanguage = settings.language
        defer { settings.language = previousLanguage }

        settings.language = .turkish

        XCTAssertEqual(LanguageSettings.selectedLanguage, .turkish)
    }
}
