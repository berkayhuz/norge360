import Foundation

/// City-specific links are intentionally limited to verified municipality pages.
enum CityResourceCatalog {
    static func task(for destinationCity: String) -> RelocationTask? {
        switch destinationCity.folding(options: .diacriticInsensitive, locale: .current).lowercased() {
        case "oslo":
            makeTask(
                slug: "city-services-oslo", title: AppStrings.cityTaskOslo,
                source: OfficialSourceCatalog.osloNewcomerGuide)
        case "bergen":
            makeTask(
                slug: "city-services-bergen", title: AppStrings.cityTaskBergen,
                source: OfficialSourceCatalog.bergenNewcomerGuide)
        case "stavanger":
            makeTask(
                slug: "city-services-stavanger", title: AppStrings.cityTaskStavanger,
                source: OfficialSourceCatalog.stavangerNewcomerGuide)
        case "trondheim":
            makeTask(
                slug: "city-services-trondheim", title: AppStrings.cityTaskTrondheim,
                source: OfficialSourceCatalog.trondheimNewcomerGuide)
        case "tromso":
            makeTask(
                slug: "city-services-tromso", title: AppStrings.cityTaskTromso,
                source: OfficialSourceCatalog.tromsoNewcomerGuide)
        default: nil
        }
    }

    private static func makeTask(slug: String, title: String, source: OfficialSource) -> RelocationTask {
        RelocationTask(
            slug: slug, title: title, taskDescription: AppStrings.cityTaskDescription,
            category: .arrival, priority: 60, officialSource: source)
    }
}
