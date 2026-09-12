import Foundation
import Testing

@testable import Norge360

struct TranslationReviewRegistryTests {
    @Test func englishSourceCopyIsReleaseReady() {
        for scope in TranslationContentScope.allCases {
            let record = TranslationReviewRegistry.record(for: .english, scope: scope)

            #expect(record.language == .english)
            #expect(record.scope == scope)
            #expect(record.status == .sourceLanguage)
            #expect(record.isReadyForRelease)
        }
        #expect(TranslationReviewRegistry.canDisplayLocalizedCopy(for: .english))
    }

    @Test func bundledLanguagesCanDisplayLocalizedCopy() {
        for language in AppLanguage.allCases where language != .english {
            for scope in TranslationContentScope.allCases {
                let record = TranslationReviewRegistry.record(for: language, scope: scope)

                #expect(record.language == language)
                #expect(record.scope == scope)
                #expect(record.status == .pendingEditorialReview)
                #expect(!record.isReadyForRelease)
            }
            #expect(TranslationReviewRegistry.canDisplayLocalizedCopy(for: language))
        }
    }
}
