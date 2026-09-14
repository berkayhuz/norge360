import SwiftUI

enum LegalDocument {
    case terms
    case privacy
    case communityGuidelines

    var title: String {
        switch self {
        case .terms:
            AppStrings.legal("terms_title")
        case .privacy:
            AppStrings.legal("privacy_title")
        case .communityGuidelines:
            AppStrings.localized("guidelines.title")
        }
    }

    var introduction: String {
        switch self {
        case .terms:
            AppStrings.legal("terms_intro")
        case .privacy:
            AppStrings.legal("privacy_intro")
        case .communityGuidelines:
            AppStrings.localized("guidelines.intro")
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .terms:
            return [
                (AppStrings.legal("informational_title"), AppStrings.legal("informational_body")),
                (AppStrings.legal("account_title"), AppStrings.legal("account_body")),
                (AppStrings.legal("sources_title"), AppStrings.legal("sources_body")),
                (AppStrings.legal("acceptable_use_title"), AppStrings.legal("acceptable_use_body")),
                (AppStrings.legal("changes_title"), AppStrings.legal("changes_body")),
            ]
        case .privacy:
            return [
                (AppStrings.legal("data_title"), AppStrings.legal("data_body")),
                (AppStrings.legal("use_title"), AppStrings.legal("use_body")),
                (AppStrings.legal("sensitive_title"), AppStrings.legal("sensitive_body")),
                (AppStrings.legal("security_title"), AppStrings.legal("security_body")),
                (AppStrings.legal("rights_title"), AppStrings.legal("rights_body")),
                (AppStrings.legal("export_title"), AppStrings.legal("export_body")),
                (AppStrings.legal("retention_title"), AppStrings.legal("retention_body")),
            ]
        case .communityGuidelines:
            return [
                (AppStrings.localized("guidelines.respect_title"), AppStrings.localized("guidelines.respect_body")),
                (AppStrings.localized("guidelines.privacy_title"), AppStrings.localized("guidelines.privacy_body")),
                (AppStrings.localized("guidelines.guidance_title"), AppStrings.localized("guidelines.guidance_body")),
                (AppStrings.localized("guidelines.reports_title"), AppStrings.localized("guidelines.reports_body")),
            ]
        }
    }

    var notice: String {
        switch self {
        case .communityGuidelines:
            AppStrings.localized("guidelines.notice")
        case .terms, .privacy:
            AppStrings.legal("review_notice")
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(document.introduction)
                    .font(.body)
                    .foregroundStyle(.secondary)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.0)
                            .font(.headline)
                        Text(section.1)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(document.notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.norgePrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .background(Color.norgeAppBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
