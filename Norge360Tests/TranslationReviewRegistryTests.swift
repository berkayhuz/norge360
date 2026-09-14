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
            #expect(!TranslationReviewRegistry.canDisplayLocalizedCopy(for: language, scope: .onboarding))
            #expect(!TranslationReviewRegistry.canDisplayLocalizedCopy(for: language, scope: .plan))
            #expect(!TranslationReviewRegistry.canDisplayLocalizedCopy(for: language, scope: .taskDescriptions))
            #expect(!TranslationReviewRegistry.canDisplayLocalizedCopy(for: language, scope: .legalNotices))
        }
    }

    @Test func generalUICanUseACompleteBundledResource() {
        for language in AppLanguage.allCases {
            #expect(TranslationReviewRegistry.canDisplayLocalizedCopy(for: language))
        }
    }

    @Test func proceduralKeyNamespacesRequireTheMatchingReviewScope() {
        #expect(TranslationReviewRegistry.scope(for: "task.tax_card.title") == .taskDescriptions)
        #expect(TranslationReviewRegistry.scope(for: "plan.progress") == .plan)
        #expect(TranslationReviewRegistry.scope(for: "legal.privacy.title") == .legalNotices)
        #expect(TranslationReviewRegistry.scope(for: "onboarding.city.question") == .onboarding)
        #expect(TranslationReviewRegistry.scope(for: "feed.error") == nil)
    }
}
