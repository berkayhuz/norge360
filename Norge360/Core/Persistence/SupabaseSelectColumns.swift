import Foundation

/// Explicit PostgREST projections for table/view-backed Codable contracts.
/// Keep these lists aligned with the fields consumed by their corresponding
/// Swift models; do not replace them with `*` or an empty select.
enum SupabaseSelectColumns {
    static let accountProfile = [
        "user_id", "preferred_locale",
    ].joined(separator: ",")

    static let relocationPlan = ["user_id", "plan", "revision"].joined(separator: ",")

    static let communityEvent = [
        "id", "host_id", "group_id", "title", "description", "area_label", "venue_name",
        "county_code", "municipality_code", "district_name", "neighborhood_name", "street_name",
        "category", "theme", "format", "age_range", "alcohol_policy", "price_type", "language",
        "is_indoor", "is_family_friendly", "is_pet_friendly", "is_accessible", "food_provided",
        "registration_required",
        "starts_at", "capacity", "created_at", "updated_at",
    ].joined(separator: ",")

    static let communityEventMedia = [
        "id", "event_id", "storage_path", "sort_order", "width", "height", "created_at",
    ].joined(separator: ",")

    static let communityEventRSVP = [
        "event_id", "user_id", "status", "created_at", "updated_at",
    ].joined(separator: ",")

    static let communityPublicProfile = [
        "user_id", "display_name", "username", "preferred_locale", "norway_status", "city_or_region",
        "public_languages", "interests", "is_public", "show_norway_status", "show_location",
        "biography", "avatar_path", "cover_path", "created_at", "updated_at",
    ].joined(separator: ",")

    static let communityGroup = [
        "id", "name", "slug", "description", "scope", "city_or_region", "visibility",
        "posting_permission", "photo_path", "created_by", "created_at",
    ].joined(separator: ",")

    static let communityGroupMembership = [
        "group_id", "user_id", "role", "created_at",
    ].joined(separator: ",")

    static let communityNotification = [
        "id", "recipient_id", "actor_id", "type", "post_id", "group_id", "event_id",
        "conversation_id", "body", "created_at", "read_at",
    ].joined(separator: ",")

    static let communityPost = [
        "id", "author_id", "group_id", "body", "title", "kind", "created_at", "updated_at",
    ].joined(separator: ",")

    static let communityComment = [
        "id", "post_id", "author_id", "body", "created_at", "updated_at",
    ].joined(separator: ",")

    static let communityMemberProfileStats = [
        "user_id", "posts_count", "likes_count", "comments_count",
    ].joined(separator: ",")

    static let communityPostMedia = [
        "id", "post_id", "storage_path", "sort_order", "width", "height", "created_at",
    ].joined(separator: ",")

    static let communityPostEditHistory = [
        "id", "post_id", "previous_body", "edited_at", "edited_by",
    ].joined(separator: ",")
}
