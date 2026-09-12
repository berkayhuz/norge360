import Foundation

struct OnboardingDraft {
    var citizenship = ""
    var isEEACitizen: Bool?
    var currentlyInNorway: Bool?
    var movingReason: MovingReason?
    var stayDuration: StayDuration?
    var destinationCityChoice = ""
    var customDestinationCity = ""
    var householdType: HouseholdType?
    var hasJobOffer: Bool?

    func profile() -> RelocationProfile? {
        let trimmedCitizenship = citizenship.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCity = destinationCityChoice == "other" ? customDestinationCity : destinationCityChoice
        let trimmedCity = selectedCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCitizenship.isEmpty, let isEEACitizen, let currentlyInNorway,
            let movingReason, let stayDuration, !trimmedCity.isEmpty,
            let householdType, let hasJobOffer
        else { return nil }
        return RelocationProfile(
            citizenship: trimmedCitizenship, isEEACitizen: isEEACitizen,
            currentlyInNorway: currentlyInNorway, movingReason: movingReason,
            stayDuration: stayDuration, destinationCity: trimmedCity,
            householdType: householdType, hasJobOffer: hasJobOffer)
    }
}
