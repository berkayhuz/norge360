import Foundation

struct RelocationProfile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let citizenship: String
    let isEEACitizen: Bool
    let currentlyInNorway: Bool
    let movingReason: MovingReason
    let stayDuration: StayDuration
    let destinationCity: String
    let householdType: HouseholdType
    let hasJobOffer: Bool

    init(
        id: UUID = UUID(), citizenship: String, isEEACitizen: Bool,
        currentlyInNorway: Bool, movingReason: MovingReason, stayDuration: StayDuration,
        destinationCity: String, householdType: HouseholdType, hasJobOffer: Bool
    ) {
        self.id = id
        self.citizenship = citizenship
        self.isEEACitizen = isEEACitizen
        self.currentlyInNorway = currentlyInNorway
        self.movingReason = movingReason
        self.stayDuration = stayDuration
        self.destinationCity = destinationCity
        self.householdType = householdType
        self.hasJobOffer = hasJobOffer
    }
}

enum MovingReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case work, study, familyImmigration, selfEmployment, other
    var id: Self { self }
    var title: String { AppStrings.localized("moving_reason.\(rawValue)") }
}

enum StayDuration: String, CaseIterable, Codable, Sendable, Identifiable {
    case underThreeMonths, threeToTwelveMonths, moreThanTwelveMonths, undecided
    var id: Self { self }
    var title: String { AppStrings.localized("stay_duration.\(rawValue)") }
}

enum HouseholdType: String, CaseIterable, Codable, Sendable, Identifiable {
    case alone, partner, children, partnerAndChildren
    var id: Self { self }
    var includesChildren: Bool { self == .children || self == .partnerAndChildren }
    var title: String { AppStrings.localized("household.\(rawValue)") }
}
