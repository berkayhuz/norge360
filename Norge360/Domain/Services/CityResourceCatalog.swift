import Foundation

/// City-specific links are intentionally limited to verified municipality pages.
enum CityResourceCatalog {
    static func task(for destinationCity: String) -> RelocationTask? {
        switch destinationCity.folding(options: .diacriticInsensitive, locale: .current).lowercased() {
        case "oslo":
            makeTask(
                slug: "city-services-oslo", titleKey: "task.city.oslo", source: OfficialSourceCatalog.osloNewcomerGuide)
        case "bergen":
            makeTask(
                slug: "city-services-bergen", titleKey: "task.city.bergen",
                source: OfficialSourceCatalog.bergenNewcomerGuide)
        case "stavanger":
            makeTask(
                slug: "city-services-stavanger", titleKey: "task.city.stavanger",
                source: OfficialSourceCatalog.stavangerNewcomerGuide)
        case "trondheim":
            makeTask(
                slug: "city-services-trondheim", titleKey: "task.city.trondheim",
                source: OfficialSourceCatalog.trondheimNewcomerGuide)
        case "tromso":
            makeTask(
                slug: "city-services-tromso", titleKey: "task.city.tromso",
                source: OfficialSourceCatalog.tromsoNewcomerGuide)
        default: nil
        }
    }

    private static func makeTask(slug: String, titleKey: String, source: OfficialSource) -> RelocationTask {
        RelocationTask(
            slug: slug, titleKey: titleKey, taskDescriptionKey: "task.city.description",
            category: .arrival, priority: 60, officialSource: source,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }
}
