import CoreGraphics
import Testing
@testable import KiroleFeature

@Suite("Haiku Section Layout")
struct HaikuSectionLayoutTests {
    @Test("Toy ball travel clamps to visible width on compact home content")
    func toyBallTravelClampsToVisibleWidth() {
        let travel = HaikuSectionLayout.toyBallHorizontalTravel(
            availableWidth: 310,
            preferredTravel: 140,
            ballSize: 46,
            edgePadding: 12
        )

        #expect(travel == 120)
    }

    @Test("Toy ball travel keeps preferred motion when width is sufficient")
    func toyBallTravelKeepsPreferredMotion() {
        let travel = HaikuSectionLayout.toyBallHorizontalTravel(
            availableWidth: 420,
            preferredTravel: 140,
            ballSize: 46,
            edgePadding: 12
        )

        #expect(travel == 140)
    }

    @Test("Toy ball travel collapses to zero when content is too narrow")
    func toyBallTravelCollapsesWhenTooNarrow() {
        let travel = HaikuSectionLayout.toyBallHorizontalTravel(
            availableWidth: 20,
            preferredTravel: 140,
            ballSize: 46,
            edgePadding: 12
        )

        #expect(travel == 0)
    }
}
