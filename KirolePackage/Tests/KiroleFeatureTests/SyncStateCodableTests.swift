import Foundation
import Testing
@testable import KiroleFeature

@Suite("SyncState codable")
struct SyncStateCodableTests {

    @Test("Legacy JSON without energyBottles decodes to 0 without throwing")
    func legacyDecodeDefaultsEnergyBottles() throws {
        let json = Data(#"{"pendingChanges": 2, "status": "synced"}"#.utf8)
        let state = try JSONDecoder().decode(SyncState.self, from: json)
        #expect(state.energyBottles == 0)
        #expect(state.pendingChanges == 2)
        #expect(state.status == .synced)
    }

    @Test("energyBottles round-trips through encode/decode")
    func roundTripsEnergyBottles() throws {
        let original = SyncState(pendingChanges: 1, status: .pending, energyBottles: 240)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncState.self, from: data)
        #expect(decoded.energyBottles == 240)
        #expect(decoded.status == .pending)
    }
}
