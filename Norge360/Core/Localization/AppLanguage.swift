import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case norwegianBokmal = "nb"
    case turkish = "tr"
    case arabic = "ar"
    case persian = "fa"
    case french = "fr"
    case spanish = "es"
    case german = "de"
    case ukrainian = "uk"
    case russian = "ru"
    case polish = "pl"
    case somali = "so"
    case tigrinya = "ti"
    case amharic = "am"
    case urdu = "ur"
    case dari = "fa-AF"

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }
    var isRightToLeft: Bool {
        switch self {
        case .arabic, .persian, .urdu, .dari:
            true
        default:
            false
        }
    }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .norwegianBokmal: "Norsk bokmål"
        case .turkish: "Türkçe"
        case .arabic: "العربية"
        case .persian: "فارسی"
        case .french: "Français"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .ukrainian: "Українська"
        case .russian: "Русский"
        case .polish: "Polski"
        case .somali: "Soomaali"
        case .tigrinya: "ትግርኛ"
        case .amharic: "አማርኛ"
        case .urdu: "اردو"
        case .dari: "دری"
        }
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    nonisolated private static let storageKey = "norge360.selectedLanguage"
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let storedLanguage = UserDefaults.standard.string(forKey: Self.storageKey)
        language = AppLanguage(rawValue: storedLanguage ?? "") ?? Self.detectedInitialLanguage()
    }

    nonisolated static var selectedLanguage: AppLanguage {
        let storedLanguage = UserDefaults.standard.string(forKey: storageKey)
        return AppLanguage(rawValue: storedLanguage ?? "") ?? detectedInitialLanguage()
    }

    nonisolated static func detectedInitialLanguage(for locale: Locale = .current) -> AppLanguage {
        let region = locale.regionCode?.uppercased()
        let language = locale.languageCode?.lowercased()

        // Prefer the App Store/device region. This keeps a supported country
        // deterministic even when the device language contains a different
        // fallback locale.
        let regionLanguages: [String: AppLanguage] = [
            "NO": .norwegianBokmal,
            "TR": .turkish,
            "DE": .german, "AT": .german, "CH": .german,
            "FR": .french, "LU": .french, "MC": .french,
            "ES": .spanish, "MX": .spanish, "AR": .spanish, "CL": .spanish, "CO": .spanish, "PE": .spanish,
            "GB": .english, "US": .english, "IE": .english, "AU": .english, "NZ": .english, "CA": .english,
            "UA": .ukrainian, "RU": .russian, "BY": .russian, "KZ": .russian,
            "PL": .polish, "SO": .somali, "ET": .amharic, "ER": .tigrinya,
            "AF": .dari, "IR": .persian, "PK": .urdu,
            "SA": .arabic, "AE": .arabic, "EG": .arabic, "JO": .arabic, "LB": .arabic,
            "MA": .arabic, "DZ": .arabic, "TN": .arabic, "IQ": .arabic,
        ]
        if let region, let detected = regionLanguages[region] { return detected }

        let languageLanguages: [String: AppLanguage] = [
            "en": .english, "nb": .norwegianBokmal, "no": .norwegianBokmal,
            "tr": .turkish, "de": .german, "fr": .french, "es": .spanish,
            "uk": .ukrainian, "ru": .russian, "pl": .polish, "so": .somali,
            "ti": .tigrinya, "am": .amharic, "ur": .urdu, "ar": .arabic,
        ]
        if let language, let detected = languageLanguages[language] { return detected }
        if language == "fa" {
            return locale.identifier.lowercased().contains("af") ? .dari : .persian
        }
        return .norwegianBokmal
    }

}
