import SwiftUI

struct LanguagePicker: View {
    @EnvironmentObject private var languageSettings: LanguageSettings

    var body: some View {
        Menu {
            Picker(AppStrings.language, selection: $languageSettings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(languagePickerTitle(for: language)).tag(language)
                }
            }
        } label: {
            Label(AppStrings.language, systemImage: "globe")
        }
        .accessibilityLabel(AppStrings.language)
    }

    private func languagePickerTitle(for language: AppLanguage) -> String {
        guard !TranslationReviewRegistry.canDisplayLocalizedCopy(for: language, scope: .onboarding) else {
            return language.nativeName
        }
        return "\(language.nativeName) — \(AppStrings.translationPending)"
    }
}
