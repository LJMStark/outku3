import Testing
import Foundation
@testable import KiroleFeature

@Suite("Gamify Storage Tests")
struct GamifyStorageTests {
    
    @Test("Verify consecutiveDays and energyBlocks store and retrieve correctly")
    func testGamifyProperties() async {
        let storage = LocalStorage.shared
        
        // Reset state for testing
        await storage.saveConsecutiveDays(0)
        await storage.saveEnergyBlocks(0)
        
        let initialDays = await storage.loadConsecutiveDays()
        let initialBlocks = await storage.loadEnergyBlocks()
        
        #expect(initialDays == 0)
        #expect(initialBlocks == 0)
        
        await storage.saveConsecutiveDays(3)
        await storage.saveEnergyBlocks(50)
        
        let newDays = await storage.loadConsecutiveDays()
        let newBlocks = await storage.loadEnergyBlocks()
        
        #expect(newDays == 3)
        #expect(newBlocks == 50)
    }
}
