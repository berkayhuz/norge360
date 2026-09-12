import Foundation

/// Explore ranking deliberately uses only explicit, explainable community
/// signals. It does not use private relocation answers, message content, or
/// engagement-maximising scores.
enum CommunityDiscoveryRules {
    enum Surface { case home, explore }

    static func recommendedPosts(
        from items: [CommunityFeedItem],
        joinedGroupIDs: Set<UUID>
    ) -> [CommunityFeedItem] {
        items.sorted { lhs, rhs in
            let lhsIsFromJoinedGroup = lhs.post.groupID.map(joinedGroupIDs.contains) ?? false
            let rhsIsFromJoinedGroup = rhs.post.groupID.map(joinedGroupIDs.contains) ?? false

            if lhsIsFromJoinedGroup != rhsIsFromJoinedGroup {
                return lhsIsFromJoinedGroup
            }
            return lhs.post.createdAt > rhs.post.createdAt
        }
    }

    static func latestPosts(from items: [CommunityFeedItem]) -> [CommunityFeedItem] {
        items.sorted { $0.post.createdAt > $1.post.createdAt }
    }

    /// Used by the chronological refresh contract: posts created after the
    /// last successful refresh appear before the already-seen timeline.
    static func postsAdded(since lastRefresh: Date, in items: [CommunityFeedItem]) -> [CommunityFeedItem] {
        latestPosts(from: items.filter { $0.post.createdAt > lastRefresh })
    }

    /// The For You feed is intentionally explainable: joined-group relevance
    /// and recency decide the broad tier, while a per-surface session salt
    /// varies otherwise comparable posts. Chronological views never use this.
    static func forYouPosts(
        from items: [CommunityFeedItem],
        joinedGroupIDs: Set<UUID>,
        surface: Surface,
        refreshToken: Int,
        seenPostIDs: Set<UUID> = []
    ) -> [CommunityFeedItem] {
        let now = Date.now
        return items.sorted { lhs, rhs in
            let lhsWasSeen = seenPostIDs.contains(lhs.id)
            let rhsWasSeen = seenPostIDs.contains(rhs.id)
            if lhsWasSeen != rhsWasSeen {
                // Keep posts the member has not reached above the already
                // viewed portion of the session feed.
                return !lhsWasSeen
            }

            let lhsTier = relevanceTier(lhs, joinedGroupIDs: joinedGroupIDs, now: now)
            let rhsTier = relevanceTier(rhs, joinedGroupIDs: joinedGroupIDs, now: now)
            if lhsTier != rhsTier { return lhsTier > rhsTier }

            // Different salts guarantee that Home and Explore do not merely
            // render the same ordered list. A pull-to-refresh changes only the
            // tie-breaker, retaining the useful relevance and recency tier.
            let lhsTie = presentationTieBreak(lhs, surface: surface, refreshToken: refreshToken)
            let rhsTie = presentationTieBreak(rhs, surface: surface, refreshToken: refreshToken)
            if lhsTie != rhsTie { return lhsTie > rhsTie }
            return lhs.post.createdAt > rhs.post.createdAt
        }
    }

    private static func relevanceTier(_ item: CommunityFeedItem, joinedGroupIDs: Set<UUID>, now: Date) -> Int {
        let isJoinedGroup = item.post.groupID.map(joinedGroupIDs.contains) ?? false
        let ageHours = max(0, now.timeIntervalSince(item.post.createdAt) / 3_600)
        let recencyTier: Int
        switch ageHours {
        case ..<6: recencyTier = 4
        case ..<24: recencyTier = 3
        case ..<72: recencyTier = 2
        default: recencyTier = 1
        }
        return (isJoinedGroup ? 10 : 0) + recencyTier
    }

    private static func stableTieBreak(id: UUID, surface: Surface, refreshToken: Int) -> UInt64 {
        let salt = surface == .home ? 0x9E37_79B9 : 0x85EB_CA6B
        var value = UInt64(bitPattern: Int64(id.uuidString.hashValue))
        value ^= UInt64(truncatingIfNeeded: salt &+ refreshToken &* 1_103_515_245)
        value &*= 0xff51_afd7_ed55_8ccd
        value ^= value >> 33
        return value
    }

    private static func presentationTieBreak(
        _ item: CommunityFeedItem,
        surface: Surface,
        refreshToken: Int
    ) -> Double {
        let random = Double(stableTieBreak(id: item.id, surface: surface, refreshToken: refreshToken) % 10_000) / 10_000
        // A modest 18% promotion means image posts win more positions within
        // the same relevance/recency tier, but a text post with a strong draw
        // still appears ahead often. It is not an "all photos first" rule.
        return random + (item.media.isEmpty ? 0 : 0.18)
    }
}
