import Foundation

enum AppStrings {
    static func localized(_ key: String) -> String {
        let selectedLanguage = LanguageSettings.selectedLanguage
        let displayLanguage =
            TranslationReviewRegistry.canDisplayLocalizedCopy(for: selectedLanguage) ? selectedLanguage : .english
        let tables = ["Localizable", "FeedUI", "ProfileUI", "MessagesUI", "InterfaceUI"]
        for language in [displayLanguage, .english] {
            let bundle = localizedBundle(for: language)
            for table in tables {
                let value = bundle.localizedString(forKey: key, value: key, table: table)
                if value != key { return value }
            }
        }
        return key
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
    static func auth(_ key: String) -> String { localized("auth.\(key)") }
    static func legal(_ key: String) -> String { localized("legal.\(key)") }
    static var createPlan: String { localized("welcome.create_plan") }
    static var onboardingNext: String { localized("onboarding.next") }
    static var onboardingBack: String { localized("onboarding.back") }
    static var onboardingCreatePlan: String { localized("onboarding.create_plan") }
    static var onboardingCancel: String { localized("onboarding.cancel") }
    static var onboardingStep: String { localized("onboarding.step") }
    static var citizenshipQuestion: String { localized("onboarding.citizenship.question") }
    static var citizenshipPlaceholder: String { localized("onboarding.citizenship.placeholder") }
    static var eeaQuestion: String { localized("onboarding.eea.question") }
    static var currentlyInNorwayQuestion: String { localized("onboarding.in_norway.question") }
    static var movingReasonQuestion: String { localized("onboarding.reason.question") }
    static var stayQuestion: String { localized("onboarding.stay.question") }
    static var cityQuestion: String { localized("onboarding.city.question") }
    static var otherMunicipality: String { localized("onboarding.city.other") }
    static var otherMunicipalityPlaceholder: String { localized("onboarding.city.other_placeholder") }
    static var householdQuestion: String { localized("onboarding.household.question") }
    static var jobOfferQuestion: String { localized("onboarding.job_offer.question") }
    static var selectOne: String { localized("onboarding.select_one") }
    static var yes: String { localized("answer.yes") }
    static var negativeAnswer: String { localized("answer.no") }
    static var tasksSection: String { localized("plan.tasks_section") }
    static var language: String { localized("language.title") }
    static var translationPending: String { localized("language.translation_pending") }
    static var calculatorTitle: String { localized("calculator.title") }
    static var calculatorIncome: String { localized("calculator.income") }
    static var calculatorAnnualSalary: String { localized("calculator.annual_salary") }
    static var calculatorLivingCosts: String { localized("calculator.living_costs") }
    static var calculatorCity: String { localized("calculator.city") }
    static var calculatorHousehold: String { localized("calculator.household") }
    static var calculatorRent: String { localized("calculator.rent") }
    static var calculatorTransport: String { localized("calculator.transport") }
    static var calculatorCustomExpenses: String { localized("calculator.custom_expenses") }
    static var calculatorResults: String { localized("calculator.results") }
    static var calculatorNetIncome: String { localized("calculator.net_income") }
    static var calculatorUtilities: String { localized("calculator.utilities") }
    static var calculatorFood: String { localized("calculator.food") }
    static var calculatorTotalExpenses: String { localized("calculator.total_expenses") }
    static var calculatorDisposableIncome: String { localized("calculator.disposable_income") }
    static var calculatorAssumptions: String { localized("calculator.assumptions") }
    static var calculatorTaxNotice: String { localized("calculator.tax_notice") }
    static var calculatorTaxLink: String { localized("calculator.tax_link") }
    static var calculatorMissingInput: String { localized("calculator.missing_input") }
    static var profileAnswers: String { localized("profile.answers") }
    static var profileCitizenship: String { localized("profile.citizenship") }
    static var profileEEA: String { localized("profile.eea") }
    static var profileInNorway: String { localized("profile.in_norway") }
    static var profileReason: String { localized("profile.reason") }
    static var profileStay: String { localized("profile.stay") }
    static var profileCity: String { localized("profile.city") }
    static var profileHousehold: String { localized("profile.household") }
    static var profileJobOffer: String { localized("profile.job_offer") }
    static var cityTaskOslo: String { localized("task.city.oslo") }
    static var cityTaskBergen: String { localized("task.city.bergen") }
    static var cityTaskStavanger: String { localized("task.city.stavanger") }
    static var cityTaskTrondheim: String { localized("task.city.trondheim") }
    static var cityTaskTromso: String { localized("task.city.tromso") }
    static var cityTaskDescription: String { localized("task.city.description") }
    static var planTitle: String { localized("plan.title") }
    static var planProgress: String { localized("plan.progress") }
    static var planInformationNote: String { localized("plan.information_note") }
    static var sourceLastVerified: String { localized("source.last_verified") }
    static var taskStatus: String { localized("task.status") }
    static var officialSource: String { localized("task.official_source") }
    static var regulatoryDisclaimer: String { localized("task.regulatory_disclaimer") }
    static var taskReportMove: String { localized("task.report_move.title") }
    static var taskReportMoveDescription: String { localized("task.report_move.description") }
    static var taskIdentity: String { localized("task.identity.title") }
    static var taskIdentityDescription: String { localized("task.identity.description") }
    static var taskTaxCard: String { localized("task.tax_card.title") }
    static var taskTaxCardDescription: String { localized("task.tax_card.description") }
    static var taskResidencePermit: String { localized("task.residence_permit.title") }
    static var taskResidencePermitDescription: String { localized("task.residence_permit.description") }
    static var taskChildren: String { localized("task.children.title") }
    static var taskChildrenDescription: String { localized("task.children.description") }
}
