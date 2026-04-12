import Testing
@testable import KiroleFeature

@Suite("Focus Energy Tests")
struct FocusEnergyTests {
    
    @Test("Verify energy bottle calculation based on minutes focused (1 bottle per 30 min)")
    func testEnergyBottleCalculation() {
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 0) == 0)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 29) == 0)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 30) == 1)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 59) == 1)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 60) == 2)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: 90) == 3)
    }
}
