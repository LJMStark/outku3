import Testing
@testable import KiroleFeature

@Suite("Focus Energy Tests")
struct FocusEnergyTests {
    
    @Test("Verify energy stage calculation based on minutes focused")
    func testEnergyStageCalculation() {
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 4) == 0)
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 5) == 1)
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 14) == 1)
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 15) == 2)
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 30) == 3)
        #expect(FocusEnergyCalculator.blocksEarned(minutes: 60) == 3)
    }
}
