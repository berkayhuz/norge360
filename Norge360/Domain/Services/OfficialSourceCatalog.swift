import Foundation

/// Curated official references used by the MVP task catalog.
/// URLs were manually checked on 8 September 2026. Content and eligibility must be rechecked before each release.
enum OfficialSourceCatalog {
    private static let verifiedDate = Date(timeIntervalSince1970: 1_788_825_600)
    private static let verificationNote =
        "Official source reviewed on 8 September 2026. "
        + "Requirements can change; verify your circumstances on the official page."

    static let udiWorkImmigration = OfficialSource(
        name: "UDI — Work immigration",
        url: URL(string: "https://www.udi.no/en/want-to-apply/work-immigration/"),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let taxDeductionCardForForeignWorkers = OfficialSource(
        name: "Skatteetaten — Tax deduction card for foreign employees",
        url: URL(string: "https://www.skatteetaten.no/en/forms/tax-deduction-card-for-foreign-citizens/"),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let identificationNumbers = OfficialSource(
        name: "Skatteetaten — Identification numbers in Norway",
        url: URL(
            string:
                "https://www.skatteetaten.no/en/person/national-registry/"
                + "identitetsnummer-og-elektronisk-id/om-identitetsnummer/"
        ),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let reportMoveToNorway = OfficialSource(
        name: "Skatteetaten — Move to Norway",
        url: URL(string: "https://www.skatteetaten.no/en/person/national-registry/moving/to-norway/"),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let educationForNewlyArrivedFamilies = OfficialSource(
        name: "Udir — Information for newly arrived parents and guardians",
        url: URL(
            string:
                "https://www.udir.no/contentassets/ab9150efc44549188ef683027b6db197/"
                + "engelsk---informasjon-om-barnehage-og-opplaring-i-norge.pdf"
        ),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let taxCalculator = OfficialSource(
        name: "Skatteetaten — Tax calculator",
        url: URL(string: "https://www.skatteetaten.no/en/person/taxes/tax-calculator/"),
        lastVerifiedAt: verifiedDate,
        verificationNote: verificationNote
    )

    static let osloNewcomerGuide = municipalSource(
        "City of Oslo — Key information sources",
        "https://www.oslo.kommune.no/english/welcome-to-oslo/before-moving-first-steps/key-information-sources/")
    static let bergenNewcomerGuide = municipalSource(
        "City of Bergen — New in Bergen", "https://www.bergen.kommune.no/english/new-in-bergen")
    static let stavangerNewcomerGuide = municipalSource(
        "City of Stavanger — English services", "https://www.stavanger.kommune.no/en/")
    static let trondheimNewcomerGuide = municipalSource(
        "Trondheim Municipality — English services", "https://trondheim.kommune.no/english/")
    static let tromsoNewcomerGuide = municipalSource(
        "Tromsø Municipality — Welcome", "https://www.tromso.kommune.no/welcome")

    private static func municipalSource(_ name: String, _ address: String) -> OfficialSource {
        OfficialSource(
            name: name, url: URL(string: address), lastVerifiedAt: verifiedDate, verificationNote: verificationNote)
    }
}
