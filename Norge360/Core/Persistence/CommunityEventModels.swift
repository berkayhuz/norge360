import Foundation

struct CommunityEventDraft: Sendable {
    let title: String
    let description: String
    let areaLabel: String
    let venueName: String?
    let countyCode: String?
    let municipalityCode: String?
    let districtName: String?
    let neighborhoodName: String?
    let streetName: String?
    let category: String?
    let theme: String?
    let format: String?
    let ageRange: String?
    let alcoholPolicy: String?
    let priceType: String?
    let language: String?
    let isIndoor: Bool
    let isFamilyFriendly: Bool
    let isPetFriendly: Bool
    let isAccessible: Bool
    let foodProvided: Bool
    let registrationRequired: Bool
    let startsAt: Date
    let capacity: Int?
    let groupID: UUID?
    let photos: [CommunityImageUpload]
}

struct CommunityEventItem: Sendable, Identifiable {
    let event: CommunityEvent
    let host: CommunityProfile?
    let currentRSVP: CommunityEventRSVP?
    let isLiked: Bool
    let likeCount: Int
    let media: [CommunityEventMedia]

    var id: UUID { event.id }
}

struct CommunityEventCounterRow: Decodable, Sendable {
    let eventID: UUID
    let likesCount: Int
    let isLikedByCurrentUser: Bool

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case likesCount = "likes_count"
        case isLikedByCurrentUser = "is_liked_by_current_user"
    }
}

protocol CommunityEventsProviding: Sendable {
    func loadUpcomingEvents(groupID: UUID?, cursor: String?, limit: Int) async throws -> CommunityPage<
        CommunityEventItem
    >
    func create(draft: CommunityEventDraft) async throws -> CommunityEvent
    func setRSVP(eventID: UUID, status: EventRSVPStatus?) async throws
    func setLiked(eventID: UUID, isLiked: Bool) async throws
    func invite(eventID: UUID, userID: UUID) async throws
    func delete(eventID: UUID) async throws
}

struct EventLikeParameters: Encodable, Sendable {
    let targetEventID: String
    let nextLiked: Bool

    init(eventID: UUID, isLiked: Bool) {
        targetEventID = eventID.uuidString
        nextLiked = isLiked
    }

    enum CodingKeys: String, CodingKey {
        case targetEventID = "target_event_id"
        case nextLiked = "next_liked"
    }
}

struct EventCounterParameters: Encodable, Sendable {
    let targetEventIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case targetEventIDs = "target_event_ids"
    }
}

struct EventCreateParameters: Encodable, Sendable {
    let eventTitle: String
    let eventDescription: String
    let eventAreaLabel: String
    let eventVenueName: String?
    let eventCountyCode: String?
    let eventMunicipalityCode: String?
    let eventDistrictName: String?
    let eventNeighborhoodName: String?
    let eventStreetName: String?
    let eventCategory: String?
    let eventTheme: String?
    let eventFormat: String?
    let eventAgeRange: String?
    let eventAlcoholPolicy: String?
    let eventPriceType: String?
    let eventLanguage: String?
    let eventIsIndoor: Bool
    let eventIsFamilyFriendly: Bool
    let eventIsPetFriendly: Bool
    let eventIsAccessible: Bool
    let eventFoodProvided: Bool
    let eventRegistrationRequired: Bool
    let eventStartsAt: String
    let eventCapacity: Int?

    init(draft: CommunityEventDraft) {
        eventTitle = draft.title
        eventDescription = draft.description
        eventAreaLabel = draft.areaLabel
        eventVenueName = draft.venueName
        eventCountyCode = draft.countyCode
        eventMunicipalityCode = draft.municipalityCode
        eventDistrictName = draft.districtName
        eventNeighborhoodName = draft.neighborhoodName
        eventStreetName = draft.streetName
        eventCategory = draft.category
        eventTheme = draft.theme
        eventFormat = draft.format
        eventAgeRange = draft.ageRange
        eventAlcoholPolicy = draft.alcoholPolicy
        eventPriceType = draft.priceType
        eventLanguage = draft.language
        eventIsIndoor = draft.isIndoor
        eventIsFamilyFriendly = draft.isFamilyFriendly
        eventIsPetFriendly = draft.isPetFriendly
        eventIsAccessible = draft.isAccessible
        eventFoodProvided = draft.foodProvided
        eventRegistrationRequired = draft.registrationRequired
        eventStartsAt = ISO8601DateFormatter().string(from: draft.startsAt)
        eventCapacity = draft.capacity
    }

    enum CodingKeys: String, CodingKey {
        case eventTitle = "event_title"
        case eventDescription = "event_description"
        case eventAreaLabel = "event_area_label"
        case eventVenueName = "event_venue_name"
        case eventCountyCode = "event_county_code"
        case eventMunicipalityCode = "event_municipality_code"
        case eventDistrictName = "event_district_name"
        case eventNeighborhoodName = "event_neighborhood_name"
        case eventStreetName = "event_street_name"
        case eventCategory = "event_category"
        case eventTheme = "event_theme"
        case eventFormat = "event_format"
        case eventAgeRange = "event_age_range"
        case eventAlcoholPolicy = "event_alcohol_policy"
        case eventPriceType = "event_price_type"
        case eventLanguage = "event_language"
        case eventIsIndoor = "event_is_indoor"
        case eventIsFamilyFriendly = "event_is_family_friendly"
        case eventIsPetFriendly = "event_is_pet_friendly"
        case eventIsAccessible = "event_is_accessible"
        case eventFoodProvided = "event_food_provided"
        case eventRegistrationRequired = "event_registration_required"
        case eventStartsAt = "event_starts_at"
        case eventCapacity = "event_capacity"
    }
}

struct GroupEventCreateParameters: Encodable, Sendable {
    let eventGroupID: UUID
    let eventTitle: String
    let eventDescription: String
    let eventAreaLabel: String
    let eventVenueName: String?
    let eventCountyCode: String?
    let eventMunicipalityCode: String?
    let eventDistrictName: String?
    let eventNeighborhoodName: String?
    let eventStreetName: String?
    let eventCategory: String?
    let eventTheme: String?
    let eventFormat: String?
    let eventAgeRange: String?
    let eventAlcoholPolicy: String?
    let eventPriceType: String?
    let eventLanguage: String?
    let eventIsIndoor: Bool
    let eventIsFamilyFriendly: Bool
    let eventIsPetFriendly: Bool
    let eventIsAccessible: Bool
    let eventFoodProvided: Bool
    let eventRegistrationRequired: Bool
    let eventStartsAt: String
    let eventCapacity: Int?

    init(groupID: UUID, draft: CommunityEventDraft) {
        eventGroupID = groupID
        eventTitle = draft.title
        eventDescription = draft.description
        eventAreaLabel = draft.areaLabel
        eventVenueName = draft.venueName
        eventCountyCode = draft.countyCode
        eventMunicipalityCode = draft.municipalityCode
        eventDistrictName = draft.districtName
        eventNeighborhoodName = draft.neighborhoodName
        eventStreetName = draft.streetName
        eventCategory = draft.category
        eventTheme = draft.theme
        eventFormat = draft.format
        eventAgeRange = draft.ageRange
        eventAlcoholPolicy = draft.alcoholPolicy
        eventPriceType = draft.priceType
        eventLanguage = draft.language
        eventIsIndoor = draft.isIndoor
        eventIsFamilyFriendly = draft.isFamilyFriendly
        eventIsPetFriendly = draft.isPetFriendly
        eventIsAccessible = draft.isAccessible
        eventFoodProvided = draft.foodProvided
        eventRegistrationRequired = draft.registrationRequired
        eventStartsAt = ISO8601DateFormatter().string(from: draft.startsAt)
        eventCapacity = draft.capacity
    }

    enum CodingKeys: String, CodingKey {
        case eventGroupID = "event_group_id"
        case eventTitle = "event_title"
        case eventDescription = "event_description"
        case eventAreaLabel = "event_area_label"
        case eventVenueName = "event_venue_name"
        case eventCountyCode = "event_county_code"
        case eventMunicipalityCode = "event_municipality_code"
        case eventDistrictName = "event_district_name"
        case eventNeighborhoodName = "event_neighborhood_name"
        case eventStreetName = "event_street_name"
        case eventCategory = "event_category"
        case eventTheme = "event_theme"
        case eventFormat = "event_format"
        case eventAgeRange = "event_age_range"
        case eventAlcoholPolicy = "event_alcohol_policy"
        case eventPriceType = "event_price_type"
        case eventLanguage = "event_language"
        case eventIsIndoor = "event_is_indoor"
        case eventIsFamilyFriendly = "event_is_family_friendly"
        case eventIsPetFriendly = "event_is_pet_friendly"
        case eventIsAccessible = "event_is_accessible"
        case eventFoodProvided = "event_food_provided"
        case eventRegistrationRequired = "event_registration_required"
        case eventStartsAt = "event_starts_at"
        case eventCapacity = "event_capacity"
    }
}

struct EventMediaInsert: Encodable, Sendable {
    let eventID: UUID
    let storagePath: String
    let sortOrder: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
        case width, height
    }
}
