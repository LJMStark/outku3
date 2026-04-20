import CoreGraphics

enum HaikuSectionLayout {
    static let preferredToyBallTravel: CGFloat = 140
    static let toyBallSize: CGFloat = 46
    static let toyBallVerticalOffset: CGFloat = 25
    static let toyBallEdgePadding: CGFloat = 12
    static let petArtworkHeight: CGFloat = 200

    static func toyBallHorizontalTravel(
        availableWidth: CGFloat,
        preferredTravel: CGFloat = preferredToyBallTravel,
        ballSize: CGFloat = toyBallSize,
        edgePadding: CGFloat = toyBallEdgePadding
    ) -> CGFloat {
        guard availableWidth > 0, ballSize > 0 else { return 0 }

        let maxSafeTravel = max(0, (availableWidth / 2) - (ballSize / 2) - edgePadding)
        return min(preferredTravel, maxSafeTravel)
    }
}
