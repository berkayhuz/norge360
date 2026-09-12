import Foundation

/// Content that needs linguistic and subject-matter review before it is shown
/// as a complete translation. Regulatory copy also requires a review against
/// its cited official Norwegian source.
enum TranslationContentScope: String, CaseIterable, Identifiable, Sendable {
    case onboarding
    case plan
    case taskDescriptions
    case legalNotices

    var id: Self { self }
}

enum TranslationReviewStatus: String, Sendable {
    /// English is the canonical source copy for the MVP.
    case sourceLanguage
    /// Translation may exist in development, but cannot be presented as reviewed copy.
    case pendingEditorialReview
    /// Reserved for a documented professional/local-editor approval.
    case approved
}

struct TranslationReviewRecord: Sendable, Equatable {
    let language: AppLanguage
    let scope: TranslationContentScope
    let status: TranslationReviewStatus
    let reviewer: String?
    let reviewedAt: Date?

    var isReadyForRelease: Bool {
        status == .sourceLanguage || (status == .approved && reviewer != nil && reviewedAt != nil)
    }
}

/// A deliberately conservative release gate. Do not mark a translation as
/// approved without a named professional/local editor and a review date.
enum TranslationReviewRegistry {
    static func record(
        for language: AppLanguage,
        scope: TranslationContentScope
    ) -> TranslationReviewRecord {
        if language == .english {
            return TranslationReviewRecord(
                language: language,
                scope: scope,
                status: .sourceLanguage,
                reviewer: nil,
                reviewedAt: nil
            )
        }

        return TranslationReviewRecord(
            language: language,
            scope: scope,
            status: .pendingEditorialReview,
            reviewer: nil,
            reviewedAt: nil
        )
    }

    /// Every supported language ships a complete UI resource bundle. The
    /// runtime gate therefore verifies that the language is part of the
    /// supported app surface; linguistic/legal editorial approval remains a
    /// separate release responsibility and is not used as a reason to show
    /// an unrelated screen in English.
    static func canDisplayLocalizedCopy(for language: AppLanguage) -> Bool {
        AppLanguage.allCases.contains(language)
    }
}
