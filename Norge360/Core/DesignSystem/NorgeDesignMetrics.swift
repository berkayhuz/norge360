import SwiftUI

/// Shared geometric vocabulary for the app. Use these for recurring UI rhythm;
/// one-off artwork placement and animation values remain feature-owned.
enum NorgeSpacing {
    static let xxs: CGFloat = 4
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
}

enum NorgeControlSize {
    /// Minimum accessible hit area for icon actions.
    static let tapTarget: CGFloat = 44
    static let compact: CGFloat = 46
    static let standard: CGFloat = 48
    static let prominent: CGFloat = 58
}

enum NorgeCornerRadius {
    static let field: CGFloat = 13
    static let smallCard: CGFloat = 14
    static let card: CGFloat = 18
    static let largeCard: CGFloat = 22
}

enum NorgeLayoutMetrics {
    static let standardListRowInset = EdgeInsets(
        top: NorgeSpacing.extraSmall,
        leading: NorgeSpacing.medium,
        bottom: NorgeSpacing.extraSmall,
        trailing: NorgeSpacing.medium
    )
    static let feedItemSpacing: CGFloat = NorgeSpacing.xxs
}

enum NorgeMediaMetrics {
    static let postSingleWidth: CGFloat = 360
    static let postCarouselWidth: CGFloat = 278
    static let postHeight: CGFloat = 260
    static let postCornerRadius: CGFloat = NorgeSpacing.small
}
